/**
 * Lightweight OpenStreetMap `opening_hours` evaluator. Full opening_hours syntax
 * is famously complex; this handles the common cases (day ranges/lists with one
 * or more time spans, plus 24/7) well enough to show an Apple-Maps-style
 * "Open / Closed" state and today's hours. Anything it can't confidently parse
 * falls back to `openNow: null`, and the caller shows the raw string.
 */

export interface HoursInfo {
  openNow: boolean | null;
  today: string | null;
}

const DAY_INDEX: Record<string, number> = { Su: 0, Mo: 1, Tu: 2, We: 3, Th: 4, Fr: 5, Sa: 6 };

export function parseOpeningHours(spec: string | undefined, now: Date = new Date()): HoursInfo {
  if (!spec) return { openNow: null, today: null };
  const s = spec.trim();
  if (/^24\s*\/\s*7$/.test(s)) return { openNow: true, today: 'Open 24 hours' };

  const weekday = now.getDay();
  const minutes = now.getHours() * 60 + now.getMinutes();

  for (const rule of s.split(';').map((r) => r.trim()).filter(Boolean)) {
    const timeMatch = rule.match(
      /(\d{1,2}:\d{2}\s*-\s*\d{1,2}:\d{2}(?:\s*,\s*\d{1,2}:\d{2}\s*-\s*\d{1,2}:\d{2})*)/,
    );
    if (!timeMatch) continue;

    const dayPart = rule.slice(0, timeMatch.index).trim();
    const days = dayPart ? parseDays(dayPart) : [0, 1, 2, 3, 4, 5, 6];
    if (!days || !days.includes(weekday)) continue;

    const ranges = timeMatch[1].split(',').map((t) => {
      const [a, b] = t.split('-').map((x) => toMinutes(x.trim()));
      return [a, b] as [number, number];
    });

    let open = false;
    for (const [a, b] of ranges) {
      if (b > a) open ||= minutes >= a && minutes < b;
      else open ||= minutes >= a || minutes < b; // crosses midnight
    }
    const today = ranges.map(([a, b]) => `${fmt(a)}–${fmt(b)}`).join(', ');
    return { openNow: open, today };
  }

  return { openNow: null, today: null };
}

function parseDays(part: string): number[] | null {
  const out = new Set<number>();
  for (const token of part.split(',').map((t) => t.trim())) {
    const range = token.match(/^([A-Za-z]{2})\s*-\s*([A-Za-z]{2})$/);
    if (range) {
      const start = DAY_INDEX[cap(range[1])];
      const end = DAY_INDEX[cap(range[2])];
      if (start === undefined || end === undefined) return null;
      for (let i = 0; i < 7; i++) {
        const idx = (start + i) % 7;
        out.add(idx);
        if (idx === end) break;
      }
    } else {
      const idx = DAY_INDEX[cap(token)];
      if (idx === undefined) return null;
      out.add(idx);
    }
  }
  return [...out];
}

function cap(s: string): string {
  return s.charAt(0).toUpperCase() + s.slice(1, 2).toLowerCase();
}

function toMinutes(hhmm: string): number {
  const [h, m] = hhmm.split(':').map(Number);
  return h * 60 + m;
}

function fmt(min: number): string {
  const h24 = Math.floor(min / 60) % 24;
  const m = min % 60;
  const period = h24 < 12 ? 'AM' : 'PM';
  const h12 = h24 % 12 === 0 ? 12 : h24 % 12;
  return m === 0 ? `${h12} ${period}` : `${h12}:${String(m).padStart(2, '0')} ${period}`;
}
