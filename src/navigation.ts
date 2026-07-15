import { Globe } from './globe';
import type { Shell } from './ui';
import { el, maneuverIcon } from './ui';
import type { LngLat } from './geo';
import { getFix } from './geoloc';
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
  private stepIndex = 0;

  constructor(
    private readonly shell: Shell,
    private readonly globe: Globe,
    private readonly originProvider?: () => LngLat | null,
  ) {}

  get isActive(): boolean {
    return this.state !== 'idle';
  }

  async directionsTo(destination: LngLat, destName: string): Promise<void> {
    this.toast('Finding a route…', 900);
    let origin = this.originProvider?.() ?? null;
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
      this.globe.updateLocation({ lon: origin[0], lat: origin[1] });
      // The route draws its own start/end pins, so drop the search markers.
      this.globe.clearPlaces();
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

    const start = el('button', { class: 'nav-start', type: 'button', textContent: 'Start' });
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

  private startGuidance(): void {
    if (!this.route) return;
    this.setState('guiding');
    this.shell.root.classList.add('is-guiding');
    this.shell.navPanel.classList.remove('is-visible');
    this.renderGuidance();
    this.renderTripBar();
    this.globe.startDrive(
      (lonlat, remaining) => this.updateGuidance(lonlat, remaining),
      () => this.arrive(),
    );
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
    if (this.route) this.updateTripBar(this.route.distance);
  }

  private updateGuidance(current: LngLat, remaining: number): void {
    if (!this.route) return;
    while (
      this.stepIndex < this.route.steps.length - 1 &&
      haversine(current, this.route.steps[this.stepIndex].location) < 30
    ) {
      this.stepIndex++;
    }
    const step = this.route.steps[this.stepIndex];
    this.updateGuidanceContent(haversine(current, step.location));
    this.updateTripBar(remaining);
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

    // "Then …" preview of the following maneuver, Apple-style.
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
    const frac = this.route.distance > 0 ? remainingMeters / this.route.distance : 0;
    const remainingSeconds = Math.max(0, this.route.duration * frac);
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
    this.globe.clearRoute();
    this.route = undefined;
    this.stepIndex = 0;
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

/** Clock time of arrival, e.g. "3:45 PM", given seconds remaining. */
function arrivalClock(remainingSeconds: number): string {
  const at = new Date(Date.now() + remainingSeconds * 1000);
  return at.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' });
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
