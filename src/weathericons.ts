import type { IconKey } from './weather';

/**
 * Compact, colorful SF-Symbols-style weather glyphs as inline SVG. Sized to the
 * container via width/height 100%.
 */
const SUN = '#FFCC00';
const MOON = '#E9EDF5';
const CLOUD = '#D7DCE5';
const CLOUD_DARK = '#AEB6C4';
const RAIN = '#5AC8FA';
const SNOW = '#D6ECFF';
const BOLT = '#FFD60A';

function svg(inner: string): string {
  return `<svg viewBox="0 0 48 48" fill="none" xmlns="http://www.w3.org/2000/svg">${inner}</svg>`;
}

const cloud = (x = 12, y = 20, s = 1, fill = CLOUD) =>
  `<g transform="translate(${x} ${y}) scale(${s})"><path d="M7 18a7 7 0 0 1 .8-13.9A9 9 0 0 1 25 6.5 6.5 6.5 0 0 1 24 19H7Z" fill="${fill}"/></g>`;

const ICONS: Record<IconKey, string> = {
  'clear-day': svg(`<circle cx="24" cy="24" r="9" fill="${SUN}"/>` +
    Array.from({ length: 8 }, (_, i) => {
      const a = (i * Math.PI) / 4;
      const x1 = 24 + Math.cos(a) * 13, y1 = 24 + Math.sin(a) * 13;
      const x2 = 24 + Math.cos(a) * 18, y2 = 24 + Math.sin(a) * 18;
      return `<line x1="${x1.toFixed(1)}" y1="${y1.toFixed(1)}" x2="${x2.toFixed(1)}" y2="${y2.toFixed(1)}" stroke="${SUN}" stroke-width="2.4" stroke-linecap="round"/>`;
    }).join('')),
  'clear-night': svg(`<path d="M31 30a12 12 0 1 1-9-19 10 10 0 0 0 9 19Z" fill="${MOON}"/>`),
  'partly-day': svg(
    `<circle cx="18" cy="17" r="6.5" fill="${SUN}"/>` +
      Array.from({ length: 8 }, (_, i) => {
        const a = (i * Math.PI) / 4;
        const x1 = 18 + Math.cos(a) * 9, y1 = 17 + Math.sin(a) * 9;
        const x2 = 18 + Math.cos(a) * 12.5, y2 = 17 + Math.sin(a) * 12.5;
        return `<line x1="${x1.toFixed(1)}" y1="${y1.toFixed(1)}" x2="${x2.toFixed(1)}" y2="${y2.toFixed(1)}" stroke="${SUN}" stroke-width="2" stroke-linecap="round"/>`;
      }).join('') +
      cloud(14, 20, 1),
  ),
  'partly-night': svg(`<path d="M22 20a8 8 0 1 1-6-12.5A6.6 6.6 0 0 0 22 20Z" fill="${MOON}"/>` + cloud(14, 21, 1)),
  cloudy: svg(cloud(9, 15, 1.05, CLOUD_DARK) + cloud(15, 20, 1.05, CLOUD)),
  fog: svg(
    cloud(12, 12, 1, CLOUD) +
      ['33', '38', '43'].map((y, i) => `<line x1="${10 + i * 2}" y1="${y}" x2="${40 - i * 2}" y2="${y}" stroke="${CLOUD_DARK}" stroke-width="2.4" stroke-linecap="round"/>`).join(''),
  ),
  drizzle: svg(cloud(12, 12, 1, CLOUD) + `<line x1="19" y1="34" x2="17" y2="39" stroke="${RAIN}" stroke-width="2.4" stroke-linecap="round"/><line x1="27" y1="34" x2="25" y2="39" stroke="${RAIN}" stroke-width="2.4" stroke-linecap="round"/>`),
  rain: svg(
    cloud(12, 10, 1, CLOUD) +
      [16, 24, 32].map((x) => `<line x1="${x}" y1="33" x2="${x - 3}" y2="41" stroke="${RAIN}" stroke-width="2.6" stroke-linecap="round"/>`).join(''),
  ),
  sleet: svg(
    cloud(12, 10, 1, CLOUD) +
      `<line x1="17" y1="33" x2="14" y2="41" stroke="${RAIN}" stroke-width="2.6" stroke-linecap="round"/>` +
      `<circle cx="26" cy="38" r="2" fill="${SNOW}"/><circle cx="33" cy="35" r="2" fill="${SNOW}"/>`,
  ),
  snow: svg(
    cloud(12, 10, 1, CLOUD) +
      [16, 24, 32].map((x, i) => `<circle cx="${x}" cy="${36 + (i % 2) * 3}" r="2.2" fill="${SNOW}"/>`).join(''),
  ),
  thunder: svg(cloud(12, 9, 1, CLOUD_DARK) + `<path d="M24 30l-6 8h5l-2 7 8-10h-5l2-5Z" fill="${BOLT}"/>`),
};

export function weatherIcon(key: IconKey): string {
  return ICONS[key] ?? ICONS.cloudy;
}
