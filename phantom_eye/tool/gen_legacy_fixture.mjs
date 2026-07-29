/**
 * Regenerates packages/pe_domain/test/fixtures/legacy_reference.json.
 *
 * The function bodies below are copied VERBATIM from the legacy TypeScript
 * app (src/geo.ts, src/routing.ts, src/navigation.ts). Running them and the
 * Dart port over identical inputs, then demanding agreement, is what proves
 * the port is faithful — far stronger than hand-written expectations, which
 * happily accept a plausible-looking transcription error.
 *
 * Usage, from the phantom_eye/ directory:
 *   node tool/gen_legacy_fixture.mjs > packages/pe_domain/test/fixtures/legacy_reference.json
 *
 * Re-run this whenever the legacy source it mirrors changes, and keep the
 * copied bodies in sync with src/.
 */
function bearingDeg(a, b) {
  const toRad = (d) => (d * Math.PI) / 180;
  const lat1 = toRad(a[1]), lat2 = toRad(b[1]), dLon = toRad(b[0] - a[0]);
  const y = Math.sin(dLon) * Math.cos(lat2);
  const x = Math.cos(lat1) * Math.sin(lat2) - Math.sin(lat1) * Math.cos(lat2) * Math.cos(dLon);
  return (Math.atan2(y, x) * 180) / Math.PI;
}
function haversine(a, b) {
  const R = 6371000;
  const toRad = (d) => (d * Math.PI) / 180;
  const dLat = toRad(b[1] - a[1]), dLon = toRad(b[0] - a[0]);
  const lat1 = toRad(a[1]), lat2 = toRad(b[1]);
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLon / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(h));
}
function formatDistance(meters) {
  const feet = meters * 3.28084;
  if (feet < 1000) return `${Math.round(feet / 10) * 10} ft`;
  const miles = meters / 1609.344;
  return `${miles.toFixed(miles < 10 ? 1 : 0)} mi`;
}
function formatDuration(seconds) {
  const min = Math.round(seconds / 60);
  if (min < 60) return `${min} min`;
  const h = Math.floor(min / 60), m = min % 60;
  return m ? `${h} hr ${m} min` : `${h} hr`;
}
function cumulative(coords) {
  const cum = [0];
  for (let i = 1; i < coords.length; i++) cum.push(cum[i - 1] + haversine(coords[i - 1], coords[i]));
  return cum;
}
// The CURRENT windowed projectOnRoute from src/navigation.ts
const PROJECT_WINDOW_SEGMENTS = 40;
function projectOnRoute(pos, coords, cum, hintSeg = -1) {
  if (coords.length < 2) return { along: 0, bearing: 0, offset: 0, seg: 0 };
  const kx = Math.cos((pos[1] * Math.PI) / 180);
  const lastSeg = coords.length - 2;
  const iStart = hintSeg >= 0 ? Math.max(0, hintSeg - PROJECT_WINDOW_SEGMENTS) : 0;
  const iEnd = hintSeg >= 0 ? Math.min(lastSeg, hintSeg + PROJECT_WINDOW_SEGMENTS) : lastSeg;
  let best = Infinity, bestAlong = cum[cum.length - 1], bestSeg = lastSeg;
  for (let i = iStart; i <= iEnd; i++) {
    const pa = coords[i], pb = coords[i + 1];
    const ax = (pa[0] - pos[0]) * kx, ay = pa[1] - pos[1];
    const bx = (pb[0] - pos[0]) * kx, by = pb[1] - pos[1];
    const abx = bx - ax, aby = by - ay;
    const len2 = abx * abx + aby * aby || 1e-12;
    let t = -(ax * abx + ay * aby) / len2;
    t = Math.max(0, Math.min(1, t));
    const cx = ax + abx * t, cy = ay + aby * t;
    const d2 = cx * cx + cy * cy;
    if (d2 < best) { best = d2; bestSeg = i; bestAlong = cum[i] + t * (cum[i + 1] - cum[i]); }
  }
  const offset = Math.sqrt(best) * 111320;
  return { along: bestAlong, bearing: bearingDeg(coords[bestSeg], coords[bestSeg + 1]), offset, seg: bestSeg };
}

// Build the same fixtures the Dart cross-check uses.
const route = [];
for (let i = 0; i < 500; i++) route.push([-122.0 + i * 0.0001, 37.0 + i * 0.00008]);
const cum = cumulative(route);

const out = { bearings: [], haversines: [], distances: [], durations: [], projections: [] };
const pts = [[-122,37],[-121.5,37.5],[0,0],[10,-20],[-74.006,40.7128],[139.69,35.68]];
for (let i = 0; i < pts.length; i++)
  for (let j = 0; j < pts.length; j++)
    if (i !== j) { out.bearings.push(bearingDeg(pts[i], pts[j])); out.haversines.push(haversine(pts[i], pts[j])); }
for (const m of [0, 1, 30.48, 100, 304, 305, 1609.344, 8046.72, 16093.44, 160934.4, 999999])
  out.distances.push(formatDistance(m));
for (const s of [0, 30, 59, 60, 600, 3599, 3600, 3900, 7200, 86400])
  out.durations.push(formatDuration(s));
let hint = -1;
for (let seg = 0; seg < 480; seg += 7) {
  const pos = [(route[seg][0]+route[seg+1][0])/2 + 0.00002, (route[seg][1]+route[seg+1][1])/2];
  const r = projectOnRoute(pos, route, cum, hint);
  hint = r.seg;
  out.projections.push({ along: r.along, bearing: r.bearing, offset: r.offset, seg: r.seg });
}
console.log(JSON.stringify(out));
