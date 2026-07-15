import { Globe } from './globe';
import type { Navigator as RouteNavigator } from './navigation';
import { toast } from './navigation';
import type { Shell } from './ui';
import { el } from './ui';
import type { LngLat } from './geo';
import { getFix, watchFixes, locationErrorText, type Fix } from './geoloc';
import { formatDistance, haversine } from './routing';

interface Waypoint {
  id: string;
  lon: number;
  lat: number;
  label: string;
}

const WAYPOINTS_KEY = 'phantom-eye.waypoints';

/**
 * Field toolkit: live GPS + follow camera, saved waypoints, and track
 * recording — the OnX-style backcountry/offroad/hunt functions.
 */
export class Field {
  private stopWatch?: () => void;
  private lastFix: Fix | null = null;

  private recording = false;
  private recordStart = 0;
  private recordDistance = 0;
  private recordLast: LngLat | null = null;
  private recordTimer?: number;

  private waypoints: Waypoint[] = loadWaypoints();
  private waypointsOpen = false;
  private surfaceElevation: number | null = null;

  constructor(
    private readonly shell: Shell,
    private readonly globe: Globe,
    private readonly nav: RouteNavigator,
  ) {
    this.globe.onFollow((on) => {
      this.shell.menuLocate.classList.toggle('is-active', on);
    });
    for (const wp of this.waypoints) {
      this.globe.addWaypoint(wp.id, wp.lon, wp.lat, wp.label);
    }
  }

  /** Current location as a plain coordinate, for routing origins. */
  lastLonLat(): LngLat | null {
    return this.lastFix?.lonlat ?? null;
  }

  // ---------- Live location + follow ----------

  /** My-location button: start tracking and enter the follow/chase camera. */
  recenter(): void {
    this.ensureWatching();
    this.shell.menuLocate.classList.add('is-busy');
    if (this.lastFix) {
      this.applyFix(this.lastFix);
      this.globe.setFollow(true);
      this.shell.menuLocate.classList.remove('is-busy');
    }
  }

  /** Locate once at boot: fly to and follow the user, if permitted. */
  async locateOnBoot(): Promise<boolean> {
    try {
      const fix = await getFix();
      this.lastFix = fix;
      this.applyFix(fix);
      this.globe.setFollow(true);
      void this.refreshElevation(fix.lonlat);
      this.updateHud();
      this.ensureWatching();
      return true;
    } catch {
      return false;
    }
  }

  private ensureWatching(): void {
    if (this.stopWatch) return;
    this.stopWatch = watchFixes(
      (fix) => this.onFix(fix),
      (err) => {
        this.shell.menuLocate.classList.remove('is-busy');
        toast(this.shell, locationErrorText(err));
        this.stopWatch?.();
        this.stopWatch = undefined;
      },
    );
  }

  private onFix(fix: Fix): void {
    const first = !this.lastFix;
    this.lastFix = fix;
    this.applyFix(fix);
    this.shell.menuLocate.classList.remove('is-busy');

    if (first) this.globe.setFollow(true);

    if (this.recording) {
      void this.globe.pushTrackPoint(fix.lonlat[0], fix.lonlat[1]);
      if (this.recordLast) this.recordDistance += haversine(this.recordLast, fix.lonlat);
      this.recordLast = fix.lonlat;
    }
    void this.refreshElevation(fix.lonlat);
    this.updateHud();
  }

  private applyFix(fix: Fix): void {
    this.globe.updateLocation({
      lon: fix.lonlat[0],
      lat: fix.lonlat[1],
      accuracy: fix.accuracy,
      heading: fix.heading,
    });
  }

  private async refreshElevation(lonlat: LngLat): Promise<void> {
    const h = await this.globe.sampleHeight(lonlat[0], lonlat[1]);
    if (h !== null && this.lastFix && this.lastFix.lonlat === lonlat) {
      this.surfaceElevation = h;
      this.updateHud();
    }
  }

  // ---------- Waypoints ----------

  addWaypointHere(): void {
    const at = this.lastFix?.lonlat ?? this.globe.cameraCenterLonLat();
    if (!at) {
      toast(this.shell, 'Pan to a spot first, then drop a waypoint.');
      return;
    }
    const wp: Waypoint = {
      id: `wp-${Date.now().toString(36)}`,
      lon: at[0],
      lat: at[1],
      label: `Waypoint ${this.waypoints.length + 1}`,
    };
    this.waypoints.push(wp);
    saveWaypoints(this.waypoints);
    this.globe.addWaypoint(wp.id, wp.lon, wp.lat, wp.label);
    toast(this.shell, `Saved ${wp.label}`);
    if (this.waypointsOpen) this.renderWaypoints();
  }

  toggleWaypoints(): void {
    this.waypointsOpen = !this.waypointsOpen;
    if (this.waypointsOpen) this.renderWaypoints();
    else this.shell.waypointsPanel.classList.remove('is-visible');
  }

  private renderWaypoints(): void {
    const close = el('button', { class: 'nav-close', type: 'button', innerHTML: '&times;' });
    close.addEventListener('click', () => this.toggleWaypoints());

    const rows = el('div', { class: 'wp-list' });
    if (this.waypoints.length === 0) {
      rows.append(el('div', { class: 'wp-empty', textContent: 'No waypoints yet. Tap the pin to drop one.' }));
    }
    for (const wp of this.waypoints) rows.append(this.waypointRow(wp));

    const sheet = el('div', { class: 'nav-sheet glass' }, [
      el('div', { class: 'nav-head' }, [
        el('div', { class: 'nav-route' }, [
          el('div', { class: 'nav-dest', textContent: 'Waypoints' }),
          el('div', { class: 'nav-meta', textContent: `${this.waypoints.length} saved` }),
        ]),
        close,
      ]),
      rows,
    ]);
    this.shell.waypointsPanel.replaceChildren(sheet);
    this.shell.waypointsPanel.classList.add('is-visible');
  }

  private waypointRow(wp: Waypoint): HTMLElement {
    const name = el('button', { class: 'wp-name', type: 'button', textContent: wp.label });
    name.addEventListener('click', () => {
      this.globe.flyToLonLat(wp.lon, wp.lat, 500, 0, -45, 2.6);
      this.toggleWaypoints();
    });
    const dir = el('button', {
      class: 'wp-action',
      type: 'button',
      title: 'Directions',
      innerHTML: iconArrow,
    });
    dir.addEventListener('click', () => {
      void this.nav.directionsTo([wp.lon, wp.lat], wp.label);
      this.toggleWaypoints();
    });
    const del = el('button', { class: 'wp-action wp-del', type: 'button', title: 'Delete', innerHTML: iconTrash });
    del.addEventListener('click', () => {
      this.globe.removeWaypoint(wp.id);
      this.waypoints = this.waypoints.filter((w) => w.id !== wp.id);
      saveWaypoints(this.waypoints);
      this.renderWaypoints();
    });
    return el('div', { class: 'wp-row' }, [name, dir, del]);
  }

  // ---------- Track recording ----------

  toggleRecording(): void {
    if (this.recording) this.stopRecording();
    else this.startRecording();
  }

  private startRecording(): void {
    this.recording = true;
    this.recordStart = Date.now();
    this.recordDistance = 0;
    this.recordLast = this.lastFix?.lonlat ?? null;
    this.globe.beginTrack();
    if (this.recordLast) void this.globe.pushTrackPoint(this.recordLast[0], this.recordLast[1]);
    this.ensureWatching();
    this.setRecordUi(true);
    this.recordTimer = window.setInterval(() => this.updateHud(), 1000);
    this.updateHud();
    toast(this.shell, 'Recording track…');
  }

  private stopRecording(): void {
    this.recording = false;
    if (this.recordTimer) window.clearInterval(this.recordTimer);
    this.recordTimer = undefined;
    this.setRecordUi(false);
    toast(this.shell, `Track saved · ${formatDistance(this.recordDistance)}`);
    this.updateHud();
  }

  private setRecordUi(on: boolean): void {
    this.shell.menuRecord.classList.toggle('is-active', on);
    const label = this.shell.menuRecord.querySelector('.menu-item-label');
    if (label) label.textContent = on ? 'Stop Recording' : 'Record Track';
  }

  // ---------- HUD ----------

  private updateHud(): void {
    const hud = this.shell.hud;
    if (this.recording) {
      hud.className = 'hud is-visible is-recording';
      hud.replaceChildren(
        el('span', { class: 'hud-rec-dot' }),
        el('span', {
          class: 'hud-line',
          textContent: `REC · ${formatDistance(this.recordDistance)} · ${clock(Date.now() - this.recordStart)}`,
        }),
      );
      return;
    }
    if (this.lastFix) {
      const [lon, lat] = this.lastFix.lonlat;
      const elev = this.lastFix.altitude ?? this.surfaceElevation;
      const parts = [formatCoord(lat, lon)];
      if (elev !== null && elev !== undefined) parts.push(`${Math.round(elev * 3.28084)} ft`);
      hud.className = 'hud is-visible';
      hud.replaceChildren(el('span', { class: 'hud-line', textContent: parts.join('  ·  ') }));
      return;
    }
    hud.className = 'hud';
  }
}

// ---------- helpers ----------

function loadWaypoints(): Waypoint[] {
  try {
    const raw = localStorage.getItem(WAYPOINTS_KEY);
    if (!raw) return [];
    const parsed = JSON.parse(raw);
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
}

function saveWaypoints(list: Waypoint[]): void {
  try {
    localStorage.setItem(WAYPOINTS_KEY, JSON.stringify(list));
  } catch {
    /* ignore private-mode storage failures */
  }
}

function formatCoord(lat: number, lon: number): string {
  const ns = lat >= 0 ? 'N' : 'S';
  const ew = lon >= 0 ? 'E' : 'W';
  return `${Math.abs(lat).toFixed(5)}° ${ns}, ${Math.abs(lon).toFixed(5)}° ${ew}`;
}

function clock(ms: number): string {
  const total = Math.floor(ms / 1000);
  const h = Math.floor(total / 3600);
  const m = Math.floor((total % 3600) / 60);
  const s = total % 60;
  const pad = (n: number) => String(n).padStart(2, '0');
  return h > 0 ? `${h}:${pad(m)}:${pad(s)}` : `${m}:${pad(s)}`;
}

const iconArrow =
  '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"><path d="M12 2 22 12 12 22 2 12Z"/><path d="M9 13v-2a2 2 0 0 1 2-2h4"/><path d="M13 6l3 3-3 3"/></svg>';
const iconTrash =
  '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><path d="M4 7h16"/><path d="M9 7V5a1 1 0 0 1 1-1h4a1 1 0 0 1 1 1v2"/><path d="M6 7l1 13h10l1-13"/></svg>';
