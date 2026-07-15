/**
 * Selectable colors and icons for user waypoints. Icon glyphs are stroke-based
 * 24×24 inner SVG, drawn inside the teardrop pin head (same convention as the
 * category glyphs), so waypoints render as pins just like the category pins.
 */

export interface WaypointIcon {
  id: string;
  glyph: string;
}

export const DEFAULT_WAYPOINT_COLOR = '#FF9500';
export const DEFAULT_WAYPOINT_ICON = 'flag';

export const WAYPOINT_COLORS = [
  '#FF3B30',
  '#FF9500',
  '#FFCC00',
  '#34C759',
  '#00C7BE',
  '#0A84FF',
  '#5E5CE6',
  '#BF5AF2',
  '#FF2D55',
  '#8E8E93',
];

export const WAYPOINT_ICONS: WaypointIcon[] = [
  { id: 'flag', glyph: '<path d="M6 21V4"/><path d="M6 4h11l-2 4 2 4H6"/>' },
  { id: 'star', glyph: '<path d="M12 3.5l2.6 5.4 5.9.8-4.3 4.1 1 5.9L12 17l-5.2 2.7 1-5.9-4.3-4.1 5.9-.8Z"/>' },
  { id: 'home', glyph: '<path d="M4 11l8-6 8 6"/><path d="M6 10v9h12v-9"/>' },
  { id: 'tent', glyph: '<path d="M12 4 3 20h18L12 4Z"/><path d="M12 4v16"/>' },
  { id: 'peak', glyph: '<path d="M3 20l6-11 4 6 2-3 6 8Z"/>' },
  { id: 'tree', glyph: '<path d="M12 3 6 12h3l-3 5h12l-3-5h3L12 3Z"/><path d="M12 17v4"/>' },
  { id: 'fish', glyph: '<path d="M3 12c4-5 11-5 15 0-4 5-11 5-15 0Z"/><path d="M18 12l3-2v4l-3-2"/>' },
  { id: 'camera', glyph: '<rect x="3" y="8" width="18" height="11" rx="2"/><circle cx="12" cy="13.5" r="3.2"/><path d="M8 8l1.4-2.2h5.2L16 8"/>' },
  { id: 'anchor', glyph: '<circle cx="12" cy="5" r="2"/><path d="M12 7v13"/><path d="M6 12H4a8 8 0 0 0 16 0h-2"/><path d="M8 10H4M20 10h-4"/>' },
  { id: 'heart', glyph: '<path d="M12 20s-7-4.6-7-10a4 4 0 0 1 7-2 4 4 0 0 1 7 2c0 5.4-7 10-7 10Z"/>' },
  { id: 'dot', glyph: '' },
];

export function waypointGlyph(id?: string): string {
  return WAYPOINT_ICONS.find((i) => i.id === id)?.glyph ?? WAYPOINT_ICONS[0].glyph;
}
