import 'package:pe_core/pe_core.dart';
import 'package:pe_domain/pe_domain.dart';
import 'package:test/test.dart';

LatLngBounds _box({
  required double centerLat,
  required double centerLon,
  required double span,
}) => LatLngBounds(
  south: centerLat - span / 2,
  north: centerLat + span / 2,
  west: centerLon - span / 2,
  east: centerLon + span / 2,
);

void main() {
  const planner = DownloadAreaPlanner();

  group('tile math', () {
    test('lonToTileX spans the world at each zoom', () {
      expect(lonToTileX(-180, 0), 0);
      expect(lonToTileX(-180, 1), 0);
      expect(lonToTileX(0, 1), 1);
      expect(lonToTileX(-180, 2), 0);
      expect(lonToTileX(-90, 2), 1);
      expect(lonToTileX(0, 2), 2);
      expect(lonToTileX(90, 2), 3);
    });

    test('latToTileY grows southward', () {
      // At zoom 1 the northern hemisphere is row 0, southern row 1.
      expect(latToTileY(45, 1), 0);
      expect(latToTileY(-45, 1), 1);
      // North is always a lower index than south.
      expect(latToTileY(60, 8), lessThan(latToTileY(-60, 8)));
    });

    test('latToTileY clamps at the Mercator limit instead of blowing up', () {
      // The legacy version had no clamp: tan/1-over-cos at +/-90 produced
      // Infinity or NaN tile indices.
      for (final lat in [90.0, -90.0, 89.9999, -89.9999]) {
        final y = latToTileY(lat, 10);
        expect(y.isFinite, isTrue, reason: 'lat $lat');
        expect(y, inInclusiveRange(0, 1023), reason: 'lat $lat');
      }
    });

    test('baseZoomForSpan is clamped to 3..17', () {
      expect(baseZoomForSpan(360), 3, reason: 'whole world clamps up to 3');
      expect(baseZoomForSpan(1e-9), 17, reason: 'a tiny span clamps to 17');
      expect(baseZoomForSpan(0), 17, reason: 'zero span must not divide by 0');
    });

    test('baseZoomForSpan increases as the span shrinks', () {
      var previous = 0;
      for (final span in [10.0, 1.0, 0.1, 0.01]) {
        final z = baseZoomForSpan(span);
        expect(z, greaterThanOrEqualTo(previous));
        previous = z;
      }
    });
  });

  group('rejections', () {
    test('null bounds', () {
      final p = planner.plan(null);
      expect(p.isRejected, isTrue);
      expect(p.rejection, DownloadRejection.noBounds);
    });

    test('an area wider than 4 degrees', () {
      final p = planner.plan(_box(centerLat: 37, centerLon: -122, span: 5));
      expect(p.rejection, DownloadRejection.areaTooLarge);
    });

    test('exactly 4 degrees is allowed', () {
      final p = planner.plan(_box(centerLat: 37, centerLon: -122, span: 4));
      expect(p.isRejected, isFalse);
    });

    test('a tall narrow area is judged on its larger span', () {
      // Narrow in longitude but 5 degrees tall: the legacy code would have
      // accepted this for zoom purposes while rejecting it here, an
      // inconsistency. Both now use the same span.
      const tall = LatLngBounds(south: 35, north: 40, west: -122, east: -121.9);
      expect(planner.plan(tall).rejection, DownloadRejection.areaTooLarge);
    });
  });

  group('planning a normal area', () {
    final bounds = _box(centerLat: 37.77, centerLon: -122.42, span: 0.05);

    test('produces tiles within the cap', () {
      final p = planner.plan(bounds);
      expect(p.isRejected, isFalse);
      expect(p.tileCount, greaterThan(0));
      expect(p.tileCount, lessThanOrEqualTo(kMaxDownloadTiles));
    });

    test('covers three consecutive zoom levels', () {
      final p = planner.plan(bounds);
      expect(p.zoomLevels.length, 3);
      for (var i = 1; i < p.zoomLevels.length; i++) {
        expect(p.zoomLevels[i], p.zoomLevels[i - 1] + 1);
      }
    });

    test('every tile is unique', () {
      final p = planner.plan(bounds);
      expect(p.tiles.toSet().length, p.tileCount);
    });

    test('tile URLs point at the OSM host', () {
      final p = planner.plan(bounds);
      final url = p.tiles.first.urlOn(kOsmTileBase);
      expect(url, startsWith('https://tile.openstreetmap.org/'));
      expect(url, endsWith('.png'));
    });
  });

  group('the 500-tile cap is unreachable with the default settings', () {
    // Measured claim, not a guess: because baseZoomForSpan scales zoom
    // inversely with the span, the base level is always ~1-2 tiles across, so
    // three levels never approach 500. This means the legacy
    // column-by-column truncation was LATENT rather than user-facing — worth
    // recording, since it is easy to mistake for an active bug.
    test('no allowed area comes close to the cap', () {
      var worst = 0;
      for (final span in [0.001, 0.01, 0.1, 0.5, 1.0, 2.0, 3.0, 3.9, 4.0]) {
        for (final lat in [0.0, 20.0, 37.0, 50.0, 60.0, 70.0, 80.0]) {
          final p = planner.plan(
            _box(centerLat: lat, centerLon: -122, span: span),
          );
          if (p.tileCount > worst) worst = p.tileCount;
        }
      }
      expect(
        worst,
        lessThan(kMaxDownloadTiles),
        reason: 'measured worst case across spans and latitudes',
      );
    });

    test('both strategies agree exactly while under the cap', () {
      const legacy = DownloadAreaPlanner(allocateBudgetAcrossZooms: false);
      for (final span in [0.01, 0.5, 3.9]) {
        final area = _box(centerLat: 37, centerLon: -122, span: span);
        final fixed = planner.plan(area);
        final old = legacy.plan(area);
        expect(fixed.tiles.toSet(), old.tiles.toSet(), reason: 'span $span');
      }
    });
  });

  group('budget allocation, where the cap can actually bite', () {
    // Forcing more zoom levels makes the budget binding, which is the
    // configuration the allocation exists to protect: if zoomLevelsDeep ever
    // grows, or baseZoomForSpan changes, the legacy truncation becomes
    // reachable.
    final area = _box(centerLat: 37, centerLon: -122, span: 3.9);
    const deepFixed = DownloadAreaPlanner(zoomLevelsDeep: 8);
    const deepLegacy = DownloadAreaPlanner(
      zoomLevelsDeep: 8,
      allocateBudgetAcrossZooms: false,
    );

    test('the cap is genuinely binding in this configuration', () {
      expect(deepLegacy.plan(area).tileCount, kMaxDownloadTiles);
    });

    test('legacy truncation starves the deeper zooms', () {
      final p = deepLegacy.plan(area);
      expect(
        p.zoomLevels.length,
        lessThan(8),
        reason: 'deeper levels never get reached',
      );
    });

    test('allocation keeps every level represented', () {
      final p = deepFixed.plan(area);
      expect(p.tileCount, lessThanOrEqualTo(kMaxDownloadTiles));
      expect(
        p.zoomLevels.length,
        8,
        reason: 'every requested level should hold at least one tile',
      );
      for (final z in p.zoomLevels) {
        expect(p.tiles.where((t) => t.z == z), isNotEmpty, reason: 'level $z');
      }
    });
  });

  group('constants stay aligned with the original', () {
    test('cap, span limit and concurrency', () {
      expect(kMaxDownloadTiles, 500);
      expect(kMaxDownloadSpanDegrees, 4);
      expect(kDownloadConcurrency, 6);
    });
  });
}
