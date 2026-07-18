import { Globe } from './globe';
import type { Shell } from './ui';
import { el, maneuverIcon } from './ui';
import { bearingDeg, type LngLat } from './geo';
import { getFix, type Fix } from './geoloc';
import {
  fetchRoutes,
  durationForMode,
  formatDistance,
  formatDuration,
  haversine,
  type Route,
  type RouteStep,
  type TravelMode,
} from './routing';

type NavState = 'idle' | 'planning' | 'guiding';

// Require this many meters off-route AND this long spent that far off before
// rerouting — a single noisy GPS fix shouldn't trigger a reroute, only a
// genuine, sustained deviation (e.g. actually taking a different road).
const OFF_ROUTE_METERS = 55;
const OFF_ROUTE_CONFIRM_MS = 3000;

const MODE_LABELS: { id: TravelMode; label: string; icon: string }[] = [
  { id: 'driving', label: 'Drive', icon: modeIcon('car') },
  { id: 'walking', label: 'Walk', icon: modeIcon('walk') },
  { id: 'cycling', label: 'Cycle', icon: modeIcon('bike') },
];

export class Navigator {
  private state: NavState = 'idle';

  // Candidate routes (index 0 is the currently selected route).
  private routes: Route[] = [];
  private routeIdx = 0;
  private mode: TravelMode = 'driving';
  private destName = '';
  private dest: LngLat | null = null;

  private stepIndex = 0;

  // Geometry of the selected route for GPS-driven progress along the path.
  private coords: LngLat[] = [];
  private cum: number[] = [];
  private stepAlong: number[] = [];
  private total = 0;
  private arrived = false;

  // Off-route rerouting.
  private rerouting = false;
  private lastReroute = 0;
  private offRouteSince: number | null = null;

  // Last route segment matched by projectOnRoute, so the next GPS fix can
  // search a small window around it instead of rescanning the whole route
  // (routes can have thousands of points). -1 means "no hint yet, do a full
  // scan" — reset whenever the route itself changes (useRoute()).
  private lastMatchedSeg = -1;

  constructor(
    private readonly shell: Shell,
    private readonly globe: Globe,
    private readonly originProvider?: () => LngLat | null,
    private readonly requestTracking?: () => void,
  ) {}

  get isActive(): boolean {
    return this.state !== 'idle';
  }

  /** Dismiss the route-planning sheet (but never interrupt active guidance). */
  cancelPlanning(): void {
    if (this.state === 'planning') this.end();
  }

  private get route(): Route | undefined {
    return this.routes[this.routeIdx];
  }

  async directionsTo(destination: LngLat, destName: string): Promise<void> {
    this.toast('Finding routes…', 900);
    let origin = this.originProvider?.() ?? null;
    if (!origin) origin = await this.tryLocateQuietly();
    if (!origin) origin = this.globe.cameraCenterLonLat();
    if (!origin) {
      this.toast('Could not determine a starting point.');
      return;
    }

    try {
      const routes = await fetchRoutes(origin, destination);
      this.routes = routes;
      this.routeIdx = 0;
      this.dest = destination;
      this.destName = destName;
      this.arrived = false;
      this.useRoute(0);
      this.globe.updateLocation({ lon: origin[0], lat: origin[1] });
      this.globe.clearPlaces();
      this.drawRoutes();
      this.renderPlanning();
      this.setState('planning');
      this.globe.frameRoute();
    } catch (err) {
      this.toast(
        (err as Error)?.message?.includes('No route')
          ? 'No route to that place.'
          : 'Routing is unavailable right now.',
      );
    }
  }

  /** Point the geometry helpers at route `idx` and recompute along-route math. */
  private useRoute(idx: number): void {
    this.routeIdx = idx;
    const route = this.routes[idx];
    if (!route) return;
    this.stepIndex = 0;
    this.coords = route.coordinates;
    this.cum = cumulative(route.coordinates);
    this.total = this.cum[this.cum.length - 1] || route.distance;
    this.lastMatchedSeg = -1;
    this.stepAlong = route.steps.map((s) => projectOnRoute(s.location, this.coords, this.cum).along);
  }

  /** Planning view: selected route plus dimmed alternates to choose between. */
  private drawRoutes(): void {
    const selected = this.routes[this.routeIdx]?.coordinates ?? [];
    const others = this.routes.filter((_, i) => i !== this.routeIdx).map((r) => r.coordinates);
    this.globe.showRouteWithAlternates(selected, others);
  }

  // ---------- Route preview sheet ----------

  private renderPlanning(): void {
    const route = this.route;
    if (!route) return;

    const close = el('button', { class: 'nav-close', type: 'button', innerHTML: '&times;' });
    close.addEventListener('click', () => this.end());

    const start = el('button', { class: 'nav-start', type: 'button', textContent: 'Go' });
    start.addEventListener('click', () => this.startGuidance());

    const modes = el('div', { class: 'nav-modes' });
    for (const m of MODE_LABELS) {
      const btn = el(
        'button',
        { class: `nav-mode ${m.id === this.mode ? 'is-active' : ''}`, type: 'button' },
        [el('span', { class: 'nav-mode-icon', innerHTML: m.icon }), el('span', { textContent: m.label })],
      );
      btn.addEventListener('click', () => {
        this.mode = m.id;
        this.renderPlanning();
      });
      modes.append(btn);
    }

    const sheet = el('div', { class: 'nav-sheet glass' }, [
      el('div', { class: 'nav-head' }, [
        el('div', { class: 'nav-route' }, [
          el('div', { class: 'nav-dest', textContent: this.destName }),
          el('div', {
            class: 'nav-meta',
            textContent: `${formatDuration(durationForMode(route, this.mode))} · ${formatDistance(route.distance)}`,
          }),
        ]),
        close,
      ]),
      modes,
    ]);

    if (this.routes.length > 1) sheet.append(this.alternatesList());

    const steps = el('div', { class: 'nav-steps' });
    for (const s of route.steps) steps.append(this.stepRow(s));
    sheet.append(steps, start);

    this.shell.navPanel.replaceChildren(sheet);
    this.shell.navPanel.classList.add('is-visible');
  }

  private alternatesList(): HTMLElement {
    const fastest = Math.min(...this.routes.map((r) => durationForMode(r, this.mode)));
    const wrap = el('div', { class: 'nav-alts' });
    this.routes.forEach((r, i) => {
      const secs = durationForMode(r, this.mode);
      const row = el(
        'button',
        { class: `nav-alt ${i === this.routeIdx ? 'is-active' : ''}`, type: 'button' },
        [
          el('span', { class: 'nav-alt-time', textContent: formatDuration(secs) }),
          el('span', { class: 'nav-alt-dist', textContent: formatDistance(r.distance) }),
          el('span', {
            class: 'nav-alt-tag',
            textContent: secs === fastest ? 'Fastest' : `+${formatDuration(secs - fastest)}`,
          }),
        ],
      );
      row.addEventListener('click', () => {
        this.useRoute(i);
        this.drawRoutes();
        this.renderPlanning();
        this.globe.frameRoute();
      });
      wrap.append(row);
    });
    return wrap;
  }

  private stepRow(step: RouteStep): HTMLElement {
    return el('div', { class: 'nav-step' }, [
      el('div', { class: 'nav-step-icon', innerHTML: maneuverIcon(step.kind) }),
      el('div', { class: 'nav-step-text', textContent: step.instruction }),
      el('div', { class: 'nav-step-dist', textContent: formatDistance(step.distance) }),
    ]);
  }

  // ---------- Guidance ----------

  private startGuidance(): void {
    if (!this.route) return;
    this.setState('guiding');
    this.shell.root.classList.add('is-guiding');
    this.shell.navPanel.classList.remove('is-visible');
    this.renderGuidance();
    this.renderTripBar();

    // Follow the *real* GPS position from behind, Apple-Maps style.
    this.requestTracking?.();
    this.globe.beginNavigation();
    const start = this.originProvider?.() ?? this.coords[0];
    if (start) this.advance(start, true);
  }

  /** Called on every live GPS fix while guiding. */
  onLocation(fix: Fix): void {
    if (this.state === 'guiding') this.advance(fix.lonlat, false);
  }

  private advance(pos: LngLat, smoothCam: boolean): void {
    if (!this.route) return;
    const { along, bearing, offset, seg } = projectOnRoute(pos, this.coords, this.cum, this.lastMatchedSeg);
    this.lastMatchedSeg = seg;

    // Wandered off the route → ask for a fresh one, but only once we've been
    // genuinely off it for a few seconds (not just a single noisy GPS fix) —
    // this is what catches "decided to go a different way," not GPS jitter.
    if (offset > OFF_ROUTE_METERS && !this.arrived) {
      if (this.offRouteSince === null) this.offRouteSince = Date.now();
      if (Date.now() - this.offRouteSince >= OFF_ROUTE_CONFIRM_MS) void this.reroute(pos);
    } else {
      this.offRouteSince = null;
    }

    let up = this.stepAlong.findIndex((sa, i) => i > 0 && sa > along + 2);
    if (up < 0) up = this.route.steps.length - 1;
    this.stepIndex = up;

    this.updateGuidanceContent(Math.max(0, this.stepAlong[up] - along));
    const remaining = Math.max(0, this.total - along);
    this.updateTripBar(remaining);
    this.globe.updateNavCamera(bearing, smoothCam);

    if (remaining < 25 && !this.arrived) {
      this.arrived = true;
      this.arrive();
    }
  }

  private async reroute(pos: LngLat): Promise<void> {
    if (this.rerouting || !this.dest) return;
    if (Date.now() - this.lastReroute < 5000) return;
    this.rerouting = true;
    this.lastReroute = Date.now();
    this.toast('Rerouting…', 2500);
    try {
      const routes = await fetchRoutes(pos, this.dest);
      if (this.state !== 'guiding') return;
      this.routes = routes;
      this.useRoute(0);
      // Just the chosen line while actively driving — alternates are a
      // planning-time concept, not something to clutter the live nav view.
      this.globe.showRoute(this.route?.coordinates ?? []);
      // Refresh guidance/trip bar and cut the camera to the new route right
      // away, instead of waiting for the next GPS fix to catch up.
      this.advance(pos, true);
    } catch {
      this.toast("Couldn't find a new route — keeping the current one.");
    } finally {
      this.rerouting = false;
    }
  }

  private renderGuidance(): void {
    const card = el('div', { class: 'guidance-card glass' }, [
      el('div', { class: 'guidance-primary' }, [
        el('div', { class: 'guidance-icon' }),
        el('div', { class: 'guidance-text' }, [
          el('div', { class: 'guidance-dist' }),
          el('div', { class: 'guidance-instr' }),
        ]),
      ]),
      el('div', { class: 'guidance-then' }),
    ]);
    this.shell.guidance.replaceChildren(card);
    this.shell.guidance.classList.add('is-visible');
    this.updateGuidanceContent();
  }

  private renderTripBar(): void {
    const end = el('button', { class: 'trip-end', type: 'button', textContent: 'End' });
    end.addEventListener('click', () => this.end());
    const inner = el('div', { class: 'trip-inner glass' }, [
      el('div', { class: 'trip-main' }, [
        el('div', { class: 'trip-eta' }),
        el('div', { class: 'trip-sub' }),
      ]),
      end,
    ]);
    this.shell.tripBar.replaceChildren(inner);
    this.shell.tripBar.classList.add('is-visible');
    if (this.route) this.updateTripBar(this.total);
  }

  private updateGuidanceContent(distanceOverride?: number): void {
    if (!this.route) return;
    const step = this.route.steps[this.stepIndex];
    if (!step) return;
    const iconEl = this.shell.guidance.querySelector('.guidance-icon');
    const distEl = this.shell.guidance.querySelector('.guidance-dist');
    const instrEl = this.shell.guidance.querySelector('.guidance-instr');
    if (iconEl) iconEl.innerHTML = maneuverIcon(step.kind);
    if (distEl) {
      distEl.textContent =
        distanceOverride === undefined ? '' : `In ${formatDistance(distanceOverride)}`;
    }
    if (instrEl) instrEl.textContent = step.instruction;

    const next = this.route.steps[this.stepIndex + 1];
    const thenEl = this.shell.guidance.querySelector('.guidance-then');
    if (thenEl) {
      if (next && next.kind !== 'arrive') {
        thenEl.innerHTML = `Then ${maneuverIcon(next.kind)}`;
        (thenEl as HTMLElement).style.display = '';
      } else {
        (thenEl as HTMLElement).style.display = 'none';
      }
    }
  }

  private updateTripBar(remainingMeters: number): void {
    if (!this.route) return;
    const frac = this.total > 0 ? remainingMeters / this.total : 0;
    const remainingSeconds = Math.max(0, durationForMode(this.route, this.mode) * frac);
    const etaEl = this.shell.tripBar.querySelector('.trip-eta');
    const subEl = this.shell.tripBar.querySelector('.trip-sub');
    if (etaEl) etaEl.textContent = arrivalClock(remainingSeconds);
    if (subEl) {
      subEl.textContent = `${formatDuration(remainingSeconds)} · ${formatDistance(remainingMeters)}`;
    }
  }

  private arrive(): void {
    const instrEl = this.shell.guidance.querySelector('.guidance-instr');
    const distEl = this.shell.guidance.querySelector('.guidance-dist');
    const thenEl = this.shell.guidance.querySelector('.guidance-then');
    if (instrEl) instrEl.textContent = 'You have arrived';
    if (distEl) distEl.textContent = '';
    if (thenEl) (thenEl as HTMLElement).style.display = 'none';
    this.updateTripBar(0);
    window.setTimeout(() => this.end(), 2600);
  }

  end(): void {
    this.globe.endNavigation();
    this.globe.clearRoute();
    this.routes = [];
    this.dest = null;
    this.stepIndex = 0;
    this.offRouteSince = null;
    this.shell.root.classList.remove('is-guiding');
    this.shell.navPanel.classList.remove('is-visible');
    this.shell.guidance.classList.remove('is-visible');
    this.shell.tripBar.classList.remove('is-visible');
    this.setState('idle');
  }

  private setState(state: NavState): void {
    this.state = state;
  }

  private async tryLocateQuietly(): Promise<LngLat | null> {
    try {
      const fix = await getFix();
      return fix.lonlat;
    } catch {
      return null;
    }
  }

  private toast(message: string, ms = 2600): void {
    toast(this.shell, message, ms);
  }
}

/** Cumulative along-route distance (meters) for each coordinate. */
function cumulative(coords: LngLat[]): number[] {
  const cum = [0];
  for (let i = 1; i < coords.length; i++) cum.push(cum[i - 1] + haversine(coords[i - 1], coords[i]));
  return cum;
}

// How many segments each direction of a hinted last-match to search, instead
// of rescanning the whole route on every GPS fix (routes can have thousands
// of points). The vehicle moves monotonically along the route almost always,
// so a window around the last match reliably contains the true nearest
// segment in normal driving.
const PROJECT_WINDOW_SEGMENTS = 40;

/**
 * Project a point onto the route: how far along it is (meters), the heading of
 * the road there, how far off the route the point is (meters), and which
 * segment matched (feed back in as `hintSeg` on the next call to search only
 * a small window around it instead of the whole route). Uses a local
 * equirectangular approximation, accurate over the short spans between
 * vertices. Pass `hintSeg = -1` (the default) to force a full scan — used
 * for the one-off per-step projection in `useRoute()`, and naturally
 * whatever a fresh/rerouted `Navigator` starts with.
 */
function projectOnRoute(
  pos: LngLat,
  coords: LngLat[],
  cum: number[],
  hintSeg = -1,
): { along: number; bearing: number; offset: number; seg: number } {
  if (coords.length < 2) return { along: 0, bearing: 0, offset: 0, seg: 0 };
  const kx = Math.cos((pos[1] * Math.PI) / 180);
  const lastSeg = coords.length - 2;
  const iStart = hintSeg >= 0 ? Math.max(0, hintSeg - PROJECT_WINDOW_SEGMENTS) : 0;
  const iEnd = hintSeg >= 0 ? Math.min(lastSeg, hintSeg + PROJECT_WINDOW_SEGMENTS) : lastSeg;

  let best = Infinity;
  let bestAlong = cum[cum.length - 1];
  let bestSeg = lastSeg;
  for (let i = iStart; i <= iEnd; i++) {
    const pa = coords[i];
    const pb = coords[i + 1];
    const ax = (pa[0] - pos[0]) * kx;
    const ay = pa[1] - pos[1];
    const bx = (pb[0] - pos[0]) * kx;
    const by = pb[1] - pos[1];
    const abx = bx - ax;
    const aby = by - ay;
    const len2 = abx * abx + aby * aby || 1e-12;
    let t = -(ax * abx + ay * aby) / len2;
    t = Math.max(0, Math.min(1, t));
    const cx = ax + abx * t;
    const cy = ay + aby * t;
    const d2 = cx * cx + cy * cy;
    if (d2 < best) {
      best = d2;
      bestSeg = i;
      bestAlong = cum[i] + t * (cum[i + 1] - cum[i]);
    }
  }
  // best is in squared degrees-of-latitude units → convert to meters.
  const offset = Math.sqrt(best) * 111_320;
  return { along: bestAlong, bearing: bearingDeg(coords[bestSeg], coords[bestSeg + 1]), offset, seg: bestSeg };
}

/** Clock time of arrival, e.g. "3:45 PM", given seconds remaining. */
function arrivalClock(remainingSeconds: number): string {
  const at = new Date(Date.now() + remainingSeconds * 1000);
  return at.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' });
}

function modeIcon(kind: 'car' | 'walk' | 'bike'): string {
  const body = {
    car: '<path d="M5 16l1.5-5A2 2 0 0 1 8.4 9.6h7.2a2 2 0 0 1 1.9 1.4L19 16"/><rect x="4" y="16" width="16" height="3" rx="1.2"/><circle cx="8" cy="19.5" r="1.3"/><circle cx="16" cy="19.5" r="1.3"/>',
    walk: '<circle cx="13" cy="4.5" r="1.6"/><path d="M13 8l-3 4 2 2v5"/><path d="M12 14l3-1 2 3"/><path d="M10 12l-2 2"/>',
    bike: '<circle cx="6" cy="17" r="3.2"/><circle cx="18" cy="17" r="3.2"/><path d="M6 17l4-6h5l-3 6"/><path d="M10 11l2-3h3"/>',
  }[kind];
  return `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">${body}</svg>`;
}

/** Small transient message near the bottom of the screen. */
export function toast(shell: Shell, message: string, ms = 2600): void {
  const t = el('div', { class: 'toast glass', textContent: message });
  shell.root.append(t);
  requestAnimationFrame(() => t.classList.add('is-visible'));
  window.setTimeout(() => {
    t.classList.remove('is-visible');
    window.setTimeout(() => t.remove(), 300);
  }, ms);
}
