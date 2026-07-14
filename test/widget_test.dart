import 'package:flutter_test/flutter_test.dart';
import 'package:phantom_eye/data/places.dart';
import 'package:phantom_eye/map/map_controller.dart';

void main() {
  group('SearchResult.fromJson', () {
    test('parses a complete result', () {
      final r = SearchResult.fromJson({
        'displayName': 'Paris, France',
        'lon': 2.35,
        'lat': 48.85,
        'height': 3000,
      });
      expect(r.displayName, 'Paris, France');
      expect(r.lon, closeTo(2.35, 1e-9));
      expect(r.lat, closeTo(48.85, 1e-9));
      expect(r.height, 3000);
    });

    test('falls back gracefully on missing fields', () {
      final r = SearchResult.fromJson({});
      expect(r.displayName, 'Unknown');
      expect(r.lon, 0);
      expect(r.lat, 0);
      expect(r.height, 2000);
    });
  });

  group('MapController', () {
    test('starts in a sensible default state', () {
      final c = MapController();
      addTearDown(c.dispose);
      expect(c.ready.value, isFalse);
      expect(c.loading.value, isFalse);
      expect(c.mode.value, 'photoreal');
    });

    test('commands are safe before a WebView is attached', () {
      final c = MapController();
      addTearDown(c.dispose);
      // None of these should throw when there is no controller yet.
      c.queueToken('abc');
      c.setToken('abc');
      c.flyHome();
      c.search("O'Hare"); // exercises quote escaping
      c.setMode('terrain');
      expect(c.mode.value, 'terrain');
    });
  });

  group('destination data', () {
    test('has curated places with valid coordinates', () {
      expect(kPlaces, isNotEmpty);
      for (final p in kPlaces) {
        expect(p.id, isNotEmpty);
        expect(p.lon, inInclusiveRange(-180, 180));
        expect(p.lat, inInclusiveRange(-90, 90));
        expect(p.height, greaterThan(0));
      }
    });

    test('place ids are unique', () {
      final ids = kPlaces.map((p) => p.id).toSet();
      expect(ids.length, kPlaces.length);
    });
  });
}
