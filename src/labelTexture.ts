/**
 * Canvas text rasterization for road-name billboards, plus text measurement
 * shared with the collision pass's size estimates. Kept Cesium-free so it's
 * cheap to unit test in isolation.
 *
 * Rasterizing text is real CPU work, so results are cached by (variant,
 * text) and reused across every redraw — without that cache, panning would
 * re-rasterize every visible name roughly every half second.
 */

export type LabelVariant = 'place' | 'roadMajor' | 'roadMinor';

interface VariantStyle {
  font: string;
  fill: string;
  outline: string;
  outlineWidth: number;
}

const STYLES: Record<LabelVariant, VariantStyle> = {
  place: {
    font: '600 15px -apple-system, BlinkMacSystemFont, system-ui, sans-serif',
    fill: '#ffffff',
    outline: 'rgba(0,0,0,0.85)',
    outlineWidth: 3,
  },
  roadMajor: {
    font: '500 12px -apple-system, BlinkMacSystemFont, system-ui, sans-serif',
    fill: '#eef1f6',
    outline: 'rgba(0,0,0,0.85)',
    outlineWidth: 3,
  },
  roadMinor: {
    font: '500 12px -apple-system, BlinkMacSystemFont, system-ui, sans-serif',
    fill: '#eef1f6',
    outline: 'rgba(0,0,0,0.85)',
    outlineWidth: 3,
  },
};

export function fontForVariant(variant: LabelVariant): string {
  return STYLES[variant].font;
}

// Cap devicePixelRatio so ultra-high-DPR phones don't quadruple rasterization
// cost — text is cached per variant:text so this only costs once per name.
const MAX_DPR = 3;
const PADDING = 4; // CSS px around the measured text so the stroke isn't clipped

let measureCtx: CanvasRenderingContext2D | null = null;
function ctx2d(): CanvasRenderingContext2D {
  if (!measureCtx) {
    const canvas = document.createElement('canvas');
    const ctx = canvas.getContext('2d');
    if (!ctx) throw new Error('2D canvas context unavailable');
    measureCtx = ctx;
  }
  return measureCtx;
}

export function measureText(text: string, font: string): { width: number; height: number } {
  const ctx = ctx2d();
  ctx.font = font;
  const m = ctx.measureText(text);
  const width = m.width;
  const height = (m.actualBoundingBoxAscent || 11) + (m.actualBoundingBoxDescent || 4);
  return { width, height };
}

export interface LabelCanvas {
  canvas: HTMLCanvasElement;
  /** CSS-pixel size (unscaled by device pixel ratio) — what Cesium's billboard width/height should use. */
  width: number;
  height: number;
}

const MAX_CACHE_ENTRIES = 500;
const cache = new Map<string, LabelCanvas>();

/**
 * A road-name canvas, pre-rotated 90° so the canvas's "up" axis is the text's
 * reading direction — this lets a billboard's `alignedAxis` (set to the
 * road's tangent direction) orient the text along the road with no extra
 * `rotation` property needed. Place labels don't need this (they're never
 * rotated), so they're drawn upright in `getLabelCanvas`.
 */
function rasterizeRoad(text: string, style: VariantStyle, dpr: number): LabelCanvas {
  const { width: textWidth, height: textHeight } = measureText(text, style.font);
  const width = Math.ceil(textHeight + PADDING * 2);
  const height = Math.ceil(textWidth + PADDING * 2);

  const canvas = document.createElement('canvas');
  canvas.width = Math.ceil(width * dpr);
  canvas.height = Math.ceil(height * dpr);
  const ctx = canvas.getContext('2d');
  if (!ctx) throw new Error('2D canvas context unavailable');
  ctx.scale(dpr, dpr);
  ctx.translate(width / 2, height / 2);
  ctx.rotate(-Math.PI / 2);
  ctx.font = style.font;
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  ctx.lineJoin = 'round';
  ctx.lineWidth = style.outlineWidth;
  ctx.strokeStyle = style.outline;
  ctx.strokeText(text, 0, 0);
  ctx.fillStyle = style.fill;
  ctx.fillText(text, 0, 0);
  return { canvas, width, height };
}

function rasterizeUpright(text: string, style: VariantStyle, dpr: number): LabelCanvas {
  const { width: textWidth, height: textHeight } = measureText(text, style.font);
  const width = Math.ceil(textWidth + PADDING * 2);
  const height = Math.ceil(textHeight + PADDING * 2);

  const canvas = document.createElement('canvas');
  canvas.width = Math.ceil(width * dpr);
  canvas.height = Math.ceil(height * dpr);
  const ctx = canvas.getContext('2d');
  if (!ctx) throw new Error('2D canvas context unavailable');
  ctx.scale(dpr, dpr);
  ctx.font = style.font;
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  ctx.lineJoin = 'round';
  ctx.lineWidth = style.outlineWidth;
  ctx.strokeStyle = style.outline;
  ctx.strokeText(text, width / 2, height / 2);
  ctx.fillStyle = style.fill;
  ctx.fillText(text, width / 2, height / 2);
  return { canvas, width, height };
}

/** Rasterize (or reuse a cached rasterization of) a label's text for the given variant. */
export function getLabelCanvas(text: string, variant: LabelVariant): LabelCanvas {
  const key = `${variant}:${text}`;
  const hit = cache.get(key);
  if (hit) {
    // Touch for simple oldest-eviction recency ordering (Map preserves insertion order).
    cache.delete(key);
    cache.set(key, hit);
    return hit;
  }

  const style = STYLES[variant];
  const dpr = Math.min(window.devicePixelRatio || 1, MAX_DPR);
  const entry = variant === 'place' ? rasterizeUpright(text, style, dpr) : rasterizeRoad(text, style, dpr);

  cache.set(key, entry);
  if (cache.size > MAX_CACHE_ENTRIES) {
    const oldestKey = cache.keys().next().value;
    if (oldestKey !== undefined) cache.delete(oldestKey);
  }
  return entry;
}
