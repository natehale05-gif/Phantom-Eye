import 'dart:math' as math;

import 'package:pe_core/pe_core.dart';

/// Largest view span (degrees) that may be downloaded.
///
/// Ported from the `span > 4` guard in `src/offline.ts:57`. Beyond this the
/// tile count explodes and the request is refused.
const double kMaxDownloadSpanDegrees = 4;

/// Hard ceiling on tiles per download.
///
/// Ported from `MAX_TILES` in `src/offline.ts:69`.
const int kMaxDownloadTiles = 500;

/// How many tile fetches run at once.
///
/// Ported from `CONCURRENCY` in `src/offline.ts:93`. Planning does not use it;
/// it is surfaced here so the fetcher and the plan agree on one constant.
const int kDownloadConcurrency = 6;

/// OSM raster tile host. Google/Cesium tile hosts are deliberately never
/// cached — the licences forbid it.
const String kOsmTileBase = 'https://tile.openstreetmap.org';

/// One tile to fetch.
final class TileCoord {
  const TileCoord({required this.z, required this.x, required this.y});

  final int z;
  final int x;
  final int y;

  String urlOn(String base) => '$base/$z/$x/$y.png';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TileCoord && other.z == z && other.x == x && other.y == y);

  @override
  int get hashCode => Object.hash(z, x, y);

  @override
  String toString() => '$z/$x/$y';
}

/// Why a download cannot proceed.
enum DownloadRejection {
  /// No usable view bounds were available.
  noBounds,

  /// The requested area is larger than [kMaxDownloadSpanDegrees].
  areaTooLarge,

  /// The area resolved to no tiles at all.
  empty,
}

/// The outcome of planning a download: either tiles, or a reason not to.
final class DownloadPlan {
  const DownloadPlan.tiles(this.tiles, {required this.zoomLevels})
    : rejection = null;

  const DownloadPlan.rejected(this.rejection)
    : tiles = const [],
      zoomLevels = const [];

  final List<TileCoord> tiles;

  /// The zoom levels actually represented in [tiles].
  final List<int> zoomLevels;

  final DownloadRejection? rejection;

  bool get isRejected => rejection != null;
  int get tileCount => tiles.length;
}

/// Web Mercator tile X for a longitude at zoom [z].
///
/// Ported from `lon2tile` in `src/offline.ts:30`.
int lonToTileX(double lon, int z) =>
    ((lon + 180) / 360 * math.pow(2, z)).floor();

/// Web Mercator tile Y for a latitude at zoom [z].
///
/// Ported from `lat2tile` in `src/offline.ts:34`, hardened at both ends:
///  - latitude is clamped to the Web Mercator limit before projecting, since
///    the original had no clamp and `tan`/`1/cos` at ±90° produced
///    `Infinity`/`NaN` tile indices;
///  - the resulting index is clamped into range, because exactly at the limit
///    the projection lands a hair below zero (about -6e-9) and `floor` turns
///    that into -1.
int latToTileY(double lat, int z) {
  final clamped = lat.clamp(-85.05112878, 85.05112878);
  final r = clamped * math.pi / 180;
  final projected = (1 - math.log(math.tan(r) + 1 / math.cos(r)) / math.pi) / 2;
  final maxIndex = math.pow(2, z).toInt() - 1;
  return (projected * math.pow(2, z)).floor().clamp(0, maxIndex);
}

/// Map a view span in degrees to a sensible OSM zoom, clamped to 3..17.
///
/// Ported from `baseZoomFor` in `src/offline.ts:40`.
int baseZoomForSpan(double spanDegrees) {
  final z = (math.log(360 / math.max(spanDegrees, 1e-4)) / math.ln2).round();
  return z.clamp(3, 17);
}

/// Plans which OSM raster tiles to pre-cache for an area.
///
/// Pure planning only — fetching and the tile store live behind their own
/// interface, which keeps this testable and keeps the licence-sensitive host
/// list in one place.
///
/// Ported from `downloadCurrentArea` in `src/offline.ts`, with two fixes.
final class DownloadAreaPlanner {
  const DownloadAreaPlanner({
    this.maxTiles = kMaxDownloadTiles,
    this.maxSpanDegrees = kMaxDownloadSpanDegrees,
    this.zoomLevelsDeep = 3,
    this.allocateBudgetAcrossZooms = true,
  });

  final int maxTiles;
  final double maxSpanDegrees;

  /// How many zoom levels to cover, starting at the base zoom.
  final int zoomLevelsDeep;

  /// When true (the default), the tile budget is shared across zoom levels so
  /// every level gets covered. See [plan] for why this matters.
  ///
  /// Set false to reproduce the legacy column-by-column truncation.
  final bool allocateBudgetAcrossZooms;

  DownloadPlan plan(LatLngBounds? bounds) {
    if (bounds == null) {
      return const DownloadPlan.rejected(DownloadRejection.noBounds);
    }

    final span = math.max(bounds.lonSpan, bounds.latSpan);
    if (span.isNaN || span > maxSpanDegrees) {
      return const DownloadPlan.rejected(DownloadRejection.areaTooLarge);
    }

    // The legacy code measured the span two different ways: the rejection test
    // above used the larger of the two, but the zoom was chosen from longitude
    // alone. For a tall, narrow area that picked a zoom too high for the area
    // actually being covered. One span for both.
    final z0 = baseZoomForSpan(span);
    final levels = [
      for (var i = 0; i < zoomLevelsDeep; i++)
        if (z0 + i <= 18) z0 + i,
    ];
    if (levels.isEmpty) {
      return const DownloadPlan.rejected(DownloadRejection.empty);
    }

    final perLevel = <int, List<TileCoord>>{};
    for (final z in levels) {
      perLevel[z] = _tilesForLevel(bounds, z);
    }

    final selected = allocateBudgetAcrossZooms
        ? _allocateAcrossLevels(levels, perLevel)
        : _legacyTruncate(levels, perLevel);

    if (selected.isEmpty) {
      return const DownloadPlan.rejected(DownloadRejection.empty);
    }

    final covered = <int>{for (final t in selected) t.z}.toList()..sort();
    return DownloadPlan.tiles(selected, zoomLevels: covered);
  }

  List<TileCoord> _tilesForLevel(LatLngBounds b, int z) {
    final xMin = lonToTileX(b.west, z);
    final xMax = lonToTileX(b.east, z);
    // Y grows southward, so north gives the minimum.
    final yMin = latToTileY(b.north, z);
    final yMax = latToTileY(b.south, z);

    final out = <TileCoord>[];
    for (var x = math.min(xMin, xMax); x <= math.max(xMin, xMax); x++) {
      for (var y = math.min(yMin, yMax); y <= math.max(yMin, yMax); y++) {
        out.add(TileCoord(z: z, x: x, y: y));
      }
    }
    return out;
  }

  /// Share the budget across zoom levels, proportional to each level's size.
  ///
  /// The legacy version walked levels outermost, then columns, then rows, and
  /// broke out of all three loops the moment it hit 500 tiles. Since tile
  /// count roughly quadruples per zoom level, exhausting the budget would
  /// leave a west-biased strip at the base zoom and nothing at all at the
  /// higher zooms.
  ///
  /// **In practice that was latent, not user-facing.** `baseZoomForSpan`
  /// scales zoom inversely with the span, so the base level is always about
  /// one or two tiles across; measured across every allowed span and latitude,
  /// three levels top out near 340 tiles and the 500 cap is never reached. The
  /// truncation was therefore unreachable through the normal path.
  ///
  /// This allocation is kept anyway because it is strictly better and costs
  /// nothing: it makes the cap safe if [zoomLevelsDeep] grows or the zoom
  /// formula changes, either of which would make the old behaviour reachable.
  /// Levels wanting less than their share hand the remainder back, and within
  /// a level retained tiles are spread by striding rather than truncated, so
  /// coverage stays centred on the whole area.
  List<TileCoord> _allocateAcrossLevels(
    List<int> levels,
    Map<int, List<TileCoord>> perLevel,
  ) {
    final total = perLevel.values.fold<int>(0, (a, l) => a + l.length);
    if (total <= maxTiles) {
      return [for (final z in levels) ...perLevel[z]!];
    }

    // Start from an equal share, then redistribute what small levels don't use.
    final quota = <int, int>{};
    var remaining = maxTiles;
    var claimants = levels.length;
    for (final z in levels) {
      final share = remaining ~/ claimants;
      final want = perLevel[z]!.length;
      final give = math.min(share, want);
      quota[z] = give;
      remaining -= give;
      claimants--;
    }
    // Anything left over goes to the levels that still want more, deepest
    // first — those are the levels a user zooms into.
    for (final z in levels.reversed) {
      if (remaining <= 0) break;
      final want = perLevel[z]!.length - quota[z]!;
      if (want <= 0) continue;
      final extra = math.min(want, remaining);
      quota[z] = quota[z]! + extra;
      remaining -= extra;
    }

    final out = <TileCoord>[];
    for (final z in levels) {
      out.addAll(_stride(perLevel[z]!, quota[z]!));
    }
    return out;
  }

  /// Take [keep] items spread evenly across [all], always including the first.
  List<TileCoord> _stride(List<TileCoord> all, int keep) {
    if (keep >= all.length) return all;
    if (keep <= 0) return const [];
    final out = <TileCoord>[];
    for (var i = 0; i < keep; i++) {
      out.add(all[(i * all.length) ~/ keep]);
    }
    return out;
  }

  /// The legacy behaviour: fill in level/column/row order and stop dead at the
  /// cap. Kept so the bug above can be demonstrated and compared against.
  List<TileCoord> _legacyTruncate(
    List<int> levels,
    Map<int, List<TileCoord>> perLevel,
  ) {
    final out = <TileCoord>[];
    for (final z in levels) {
      for (final t in perLevel[z]!) {
        if (out.length >= maxTiles) return out;
        out.add(t);
      }
    }
    return out;
  }
}
