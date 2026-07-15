import { Globe } from './globe';
import type { Shell } from './ui';
import { el, maneuverIcon } from './ui';
import type { LngLat } from './geo';
import {
  fetchRoute,
  formatDistance,
  formatDuration,
  haversine,
  type Route,
  type RouteStep,
} from './routing';

type NavState = 'idle' | 'planning' | 'guiding';

export class Navigator {
  private state: NavState = 'idle';
  private route?: Route;
  private lastLocation?: LngLat;
  private stepIndex = 0;

  constructor(
    private readonly shell: Shell,
    private readonly globe: Globe,
  ) {}

  get isActive(): boolean {
    return this.state !== 'idle';
  }

  // ---------- My location ----------

  async locate(fly = true): Promise<LngLat | null> {
    try {
      const pos = await getPosition();
      const lonlat: LngLat = [pos.coords.longitude, pos.coords.latitude];
      this.lastLocation = lonlat;
      this.globe.showLocation(lonlat[0], lonlat[1]);
      if (fly) this.globe.flyToLonLat(lonlat[0], lonlat[1], 900, 0, -40, 2.6);
      return lonlat;
    } catch (err) {
      this.toast(locationError(err));
      return null;
    }
  }

  // ---------- Directions ----------

  async directionsTo(destination: LngLat, destName: string): Promise<void> {
    this.toast('Finding a route…', 900);
    // Prefer the user's real location; fall back to the map center.
    let origin = this.lastLocation ?? null;
    if (!origin) origin = await this.tryLocateQuietly();
    if (!origin) origin = this.globe.cameraCenterLonLat();
    if (!origin) {
      this.toast('Could not determine a starting point.');
      return;
    }

    try {
      const route = await fetchRoute(origin, destination, 'driving');
      this.route = route;
      this.stepIndex = 0;
      this.globe.showLocation(origin[0], origin[1]);
      this.globe.showRoute(route.coordinates);
      this.renderPlanning(destName, route);
      this.setState('planning');
      this.globe.frameRoute();
    } catch (err) {
      this.toast(
        (err as Error)?.message?.includes('No route')
          ? 'No driving route to that place.'
          : 'Routing is unavailable right now.',
      );
    }
  }

  private renderPlanning(destName: string, route: Route): void {
    const close = el('button', { class: 'nav-close', type: 'button', innerHTML: '&times;' });
    close.addEventListener('click', () => this.end());

    const start = el('button', {
      class: 'nav-start',
      type: 'button',
      textContent: 'Start',
    });
    start.addEventListener('click', () => this.startGuidance());

    const steps = el('div', { class: 'nav-steps' });
    for (const s of route.steps) steps.append(this.stepRow(s));

    const sheet = el('div', { class: 'nav-sheet glass' }, [
      el('div', { class: 'nav-head' }, [
        el('div', { class: 'nav-route' }, [
          el('div', { class: 'nav-dest', textContent: destName }),
          el('div', {
            class: 'nav-meta',
            textContent: `${formatDuration(route.duration)} · ${formatDistance(route.distance)}`,
          }),
        ]),
        close,
      ]),
      steps,
      start,
    ]);

    this.shell.navPanel.replaceChildren(sheet);
    this.shell.navPanel.classList.add('is-visible');
  }

  private stepRow(step: RouteStep): HTMLElement {
    return el('div', { class: 'nav-step' }, [
      el('div', { class: 'nav-step-icon', innerHTML: maneuverIcon(step.kind) }),
      el('div', { class: 'nav-step-text', textContent: step.instruction }),
      el('div', { class: 'nav-step-dist', textContent: formatDistance(step.distance) }),
    ]);
  }

  // ---------- Turn-by-turn guidance ----------

  private startGuidance(): void {
    if (!this.route) return;
    this.setState('guiding');
    this.shell.navPanel.classList.remove('is-visible');
    this.renderGuidance();

    this.globe.startDrive(
      (lonlat) => this.updateGuidance(lonlat),
      () => this.arrive(),
    );
  }

  private renderGuidance(): void {
    const exit = el('button', { class: 'guidance-exit', type: 'button', textContent: 'End' });
    exit.addEventListener('click', () => this.end());

    const card = el('div', { class: 'guidance-card glass' }, [
      el('div', { class: 'guidance-icon' }),
      el('div', { class: 'guidance-text' }, [
        el('div', { class: 'guidance-dist' }),
        el('div', { class: 'guidance-instr' }),
      ]),
      exit,
    ]);
    this.shell.guidance.replaceChildren(card);
    this.shell.guidance.classList.add('is-visible');
    this.updateGuidanceContent();
  }

  private updateGuidance(current: LngLat): void {
    if (!this.route) return;
    // Advance past steps we've effectively reached.
    while (
      this.stepIndex < this.route.steps.length - 1 &&
      haversine(current, this.route.steps[this.stepIndex].location) < 30
    ) {
      this.stepIndex++;
    }
    const step = this.route.steps[this.stepIndex];
    const dist = haversine(current, step.location);
    this.updateGuidanceContent(dist);
  }

  private updateGuidanceContent(distanceOverride?: number): void {
    if (!this.route) return;
    const step = this.route.steps[this.stepIndex];
    const iconEl = this.shell.guidance.querySelector('.guidance-icon');
    const distEl = this.shell.guidance.querySelector('.guidance-dist');
    const instrEl = this.shell.guidance.querySelector('.guidance-instr');
    if (iconEl) iconEl.innerHTML = maneuverIcon(step.kind);
    if (distEl) {
      distEl.textContent =
        distanceOverride === undefined ? '' : `In ${formatDistance(distanceOverride)}`;
    }
    if (instrEl) instrEl.textContent = step.instruction;
  }

  private arrive(): void {
    const instrEl = this.shell.guidance.querySelector('.guidance-instr');
    const distEl = this.shell.guidance.querySelector('.guidance-dist');
    if (instrEl) instrEl.textContent = 'You have arrived';
    if (distEl) distEl.textContent = '';
    window.setTimeout(() => this.end(), 2600);
  }

  end(): void {
    this.globe.clearRoute();
    this.route = undefined;
    this.stepIndex = 0;
    this.shell.navPanel.classList.remove('is-visible');
    this.shell.guidance.classList.remove('is-visible');
    this.setState('idle');
  }

  private setState(state: NavState): void {
    this.state = state;
    // Hide the destinations rail while navigating.
    this.shell.destinationsWrap.classList.toggle('is-hidden', state !== 'idle');
  }

  private async tryLocateQuietly(): Promise<LngLat | null> {
    try {
      const pos = await getPosition();
      const lonlat: LngLat = [pos.coords.longitude, pos.coords.latitude];
      this.lastLocation = lonlat;
      return lonlat;
    } catch {
      return null;
    }
  }

  private toast(message: string, ms = 2600): void {
    const t = el('div', { class: 'toast glass', textContent: message });
    this.shell.root.append(t);
    requestAnimationFrame(() => t.classList.add('is-visible'));
    window.setTimeout(() => {
      t.classList.remove('is-visible');
      window.setTimeout(() => t.remove(), 300);
    }, ms);
  }
}

function getPosition(): Promise<GeolocationPosition> {
  return new Promise((resolve, reject) => {
    if (!('geolocation' in navigator)) {
      reject(new Error('unsupported'));
      return;
    }
    navigator.geolocation.getCurrentPosition(resolve, reject, {
      enableHighAccuracy: true,
      timeout: 10000,
      maximumAge: 30000,
    });
  });
}

function locationError(err: unknown): string {
  const code = (err as GeolocationPositionError)?.code;
  if (code === 1) return 'Location permission denied.';
  if (code === 2) return 'Location unavailable.';
  if (code === 3) return 'Location request timed out.';
  return 'Could not get your location.';
}
