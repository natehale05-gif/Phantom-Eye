/// Selectable colours and icons for user waypoints.
///
/// Ported from `src/waypointstyles.ts`. Only the **ids** live here; the SVG
/// glyph for each icon is presentation and belongs to the UI package, which
/// keeps this layer Flutter-free and means a glyph redraw never touches
/// domain code.
library;

/// Default pin colour for a new waypoint.
///
/// Ported from `DEFAULT_WAYPOINT_COLOR` in `src/waypointstyles.ts:12`.
const String kDefaultWaypointColorHex = '#FF9500';

/// Default icon for a new waypoint.
///
/// Ported from `DEFAULT_WAYPOINT_ICON` in `src/waypointstyles.ts:13`.
const String kDefaultWaypointIconId = 'flag';

/// The colour swatches offered in the waypoint editor, in display order.
///
/// Ported from `WAYPOINT_COLORS` in `src/waypointstyles.ts:15`.
const List<String> kWaypointColors = [
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

/// The icon ids offered in the waypoint editor, in display order.
///
/// Ported from `WAYPOINT_ICONS` in `src/waypointstyles.ts:27`. `dot` is last
/// and deliberately has no glyph — it draws as a plain pin head.
const List<String> kWaypointIconIds = [
  'flag',
  'star',
  'home',
  'tent',
  'peak',
  'tree',
  'fish',
  'camera',
  'anchor',
  'heart',
  'dot',
];

/// Resolve a stored colour, falling back to the default.
///
/// An unrecognised value falls back rather than being drawn as-is: stored
/// data is not trusted, and a bad colour string would otherwise reach the
/// renderer.
String waypointColorOrDefault(String? colorHex) =>
    (colorHex != null && kWaypointColors.contains(colorHex))
    ? colorHex
    : kDefaultWaypointColorHex;

/// Resolve a stored icon id, falling back to the default.
///
/// Ported from `waypointGlyph` in `src/waypointstyles.ts:42`, which resolved
/// an unknown id to the first icon in the list — `flag`, the same as the
/// documented default.
String waypointIconOrDefault(String? iconId) =>
    (iconId != null && kWaypointIconIds.contains(iconId))
    ? iconId
    : kDefaultWaypointIconId;
