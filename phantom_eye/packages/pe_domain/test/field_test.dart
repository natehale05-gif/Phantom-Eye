import 'dart:convert';

import 'package:pe_core/pe_core.dart';
import 'package:pe_domain/pe_domain.dart';
import 'package:test/test.dart';

Waypoint _wp(String id, {String label = 'Camp', double metresEast = 0}) {
  final at = destinationPoint(const LngLat(-123.26, 44.56), 90, metresEast);
  return Waypoint(id: id, position: at, label: label);
}

void main() {
  group('waypoint styles', () {
    test('the documented defaults', () {
      expect(kDefaultWaypointColorHex, '#FF9500');
      expect(kDefaultWaypointIconId, 'flag');
      expect(kWaypointColors.first, '#FF3B30');
      expect(kWaypointColors, hasLength(10));
      expect(kWaypointIconIds, hasLength(11));
    });

    test('the defaults are themselves offered in the pickers', () {
      expect(kWaypointColors, contains(kDefaultWaypointColorHex));
      expect(kWaypointIconIds, contains(kDefaultWaypointIconId));
    });

    test('every colour and icon id is distinct', () {
      expect(kWaypointColors.toSet(), hasLength(kWaypointColors.length));
      expect(kWaypointIconIds.toSet(), hasLength(kWaypointIconIds.length));
    });

    test('flag leads the icon list, matching the legacy fallback', () {
      // `waypointGlyph` resolved an unknown id to WAYPOINT_ICONS[0].
      expect(kWaypointIconIds.first, kDefaultWaypointIconId);
    });

    test(
      'unrecognised stored values fall back rather than reaching the renderer',
      () {
        expect(waypointColorOrDefault('#0A84FF'), '#0A84FF');
        expect(waypointColorOrDefault(null), kDefaultWaypointColorHex);
        expect(waypointColorOrDefault(''), kDefaultWaypointColorHex);
        expect(waypointColorOrDefault('red'), kDefaultWaypointColorHex);
        expect(waypointColorOrDefault('#DEADBEEF'), kDefaultWaypointColorHex);

        expect(waypointIconOrDefault('tent'), 'tent');
        expect(waypointIconOrDefault(null), kDefaultWaypointIconId);
        expect(waypointIconOrDefault('spaceship'), kDefaultWaypointIconId);
      },
    );
  });

  group('Waypoint JSON', () {
    test('round-trips through the legacy shape', () {
      const wp = Waypoint(
        id: 'a',
        position: LngLat(-123.26, 44.56),
        label: 'Trailhead',
        colorHex: '#34C759',
        iconId: 'peak',
      );
      final json = wp.toJson();
      // The legacy app wrote lon/lat as separate keys with optional
      // color/icon; a migration can only read it back if that shape holds.
      expect(json['lon'], -123.26);
      expect(json['lat'], 44.56);
      expect(json['color'], '#34C759');
      expect(json['icon'], 'peak');

      final back = Waypoint.fromJson(json)!;
      expect(back.id, 'a');
      expect(back.position, wp.position);
      expect(back.label, 'Trailhead');
      expect(back.colorHex, '#34C759');
      expect(back.iconId, 'peak');
    });

    test('absent colour and icon stay absent, not empty strings', () {
      const wp = Waypoint(id: 'a', position: LngLat(0, 0), label: '');
      final json = wp.toJson();
      expect(json.containsKey('color'), isFalse);
      expect(json.containsKey('icon'), isFalse);
      expect(Waypoint.fromJson(json)!.colorHex, isNull);
    });

    test('unusable entries yield null so they can be dropped', () {
      expect(Waypoint.fromJson(null), isNull);
      expect(Waypoint.fromJson('nope'), isNull);
      expect(Waypoint.fromJson(const {}), isNull);
      expect(Waypoint.fromJson({'id': 'a'}), isNull, reason: 'no coordinate');
      expect(
        Waypoint.fromJson({'id': '', 'lon': 0, 'lat': 0}),
        isNull,
        reason: 'empty id',
      );
      expect(
        Waypoint.fromJson({'id': 'a', 'lon': double.nan, 'lat': 0}),
        isNull,
        reason: 'NaN coordinate',
      );
    });

    test('a missing label reads as empty rather than failing', () {
      final wp = Waypoint.fromJson({'id': 'a', 'lon': 1, 'lat': 2})!;
      expect(wp.label, '');
    });
  });

  group('WaypointStore', () {
    test('add, update and remove round-trip through storage', () async {
      final storage = InMemoryKeyValueStore();
      final store = WaypointStore(storage);

      expect(store.all(), isEmpty);
      await store.add(_wp('a'));
      await store.add(_wp('b', label: 'Spring'));
      expect(store.all().map((w) => w.id), ['a', 'b']);

      await store.update(_wp('a').copyWith(label: 'Base camp'));
      expect(store.all().first.label, 'Base camp');
      expect(store.all().map((w) => w.id), ['a', 'b'], reason: 'order kept');

      await store.remove('a');
      expect(store.all().map((w) => w.id), ['b']);

      // A second store over the same backing sees the same data.
      expect(WaypointStore(storage).all().map((w) => w.id), ['b']);
    });

    test('removing an unknown id is a no-op', () async {
      final store = WaypointStore(InMemoryKeyValueStore());
      await store.add(_wp('a'));
      await store.remove('zzz');
      expect(store.all(), hasLength(1));
    });

    test('REGRESSION: one corrupt entry does not take the list with it', () {
      // The legacy loader checked only `Array.isArray(parsed)` and handed back
      // whatever was inside, so a truncated write produced a waypoint with no
      // coordinate that broke rendering for every waypoint after it.
      final storage = InMemoryKeyValueStore({
        StorageKeys.waypoints: jsonEncode([
          {'id': 'good1', 'lon': -123.26, 'lat': 44.56, 'label': 'Kept'},
          {'id': 'broken'},
          'not even an object',
          {'id': 'good2', 'lon': -123.27, 'lat': 44.57, 'label': 'Also kept'},
        ]),
      });
      expect(WaypointStore(storage).all().map((w) => w.id), ['good1', 'good2']);
    });

    test('a corrupt blob yields an empty list, not an exception', () {
      for (final raw in ['not json', '{}', '42', '"a string"', '']) {
        final storage = InMemoryKeyValueStore({StorageKeys.waypoints: raw});
        expect(WaypointStore(storage).all(), isEmpty, reason: raw);
      }
    });

    test('a missing key yields an empty list', () {
      expect(WaypointStore(InMemoryKeyValueStore()).all(), isEmpty);
    });

    test('a write failure keeps the session working', () async {
      // Private-mode storage rejects writes; the original swallowed that and
      // carried on with the in-memory list rather than failing the tap.
      final store = WaypointStore(FailingKeyValueStore());
      await store.add(_wp('a'));
      expect(store.all().map((w) => w.id), ['a']);
    });

    test('the storage key matches the legacy one', () {
      final storage = InMemoryKeyValueStore();
      WaypointStore(storage).add(_wp('a'));
      expect(StorageKeys.waypoints, 'phantom-eye.waypoints');
    });
  });

  group('formatTrackClock', () {
    test('under an hour omits the hour field', () {
      expect(formatTrackClock(const Duration(seconds: 0)), '0:00');
      expect(formatTrackClock(const Duration(seconds: 7)), '0:07');
      expect(formatTrackClock(const Duration(seconds: 62)), '1:02');
      expect(formatTrackClock(const Duration(minutes: 7, seconds: 42)), '7:42');
      expect(
        formatTrackClock(const Duration(minutes: 59, seconds: 59)),
        '59:59',
      );
    });

    test('an hour and over pads the minutes', () {
      expect(formatTrackClock(const Duration(hours: 1)), '1:00:00');
      expect(
        formatTrackClock(const Duration(hours: 1, minutes: 2, seconds: 3)),
        '1:02:03',
      );
      expect(
        formatTrackClock(const Duration(hours: 12, minutes: 34, seconds: 56)),
        '12:34:56',
      );
    });

    test('minutes are NOT padded in the short form', () {
      // `7:42`, not `07:42` — this string sits in the HUD next to the
      // distance and the original did not pad it.
      expect(formatTrackClock(const Duration(minutes: 7)), '7:00');
    });

    test('a negative duration reads as zero rather than a minus sign', () {
      expect(formatTrackClock(const Duration(seconds: -5)), '0:00');
    });
  });

  group('TrackRecorder', () {
    LngLat east(double metres) =>
        destinationPoint(const LngLat(-123.26, 44.56), 90, metres);

    test('accumulates distance between accepted fixes', () {
      final r = TrackRecorder()..start(from: east(0));
      r.addFix(east(100));
      r.addFix(east(200));
      expect(r.distanceMeters, closeTo(200, 1));
      expect(r.points, hasLength(3));
    });

    test('seeding the start point is what captures the first leg', () {
      final seeded = TrackRecorder()..start(from: east(0));
      seeded.addFix(east(100));
      expect(seeded.distanceMeters, closeTo(100, 1));

      // Without a seed the first fix only establishes the origin.
      final unseeded = TrackRecorder()..start();
      unseeded.addFix(east(0));
      unseeded.addFix(east(100));
      expect(unseeded.distanceMeters, closeTo(100, 1));
      expect(unseeded.points, hasLength(2));
    });

    test('stationary jitter is ignored instead of inflating the distance', () {
      // A parked phone emits fixes wandering a few metres; the original summed
      // every one, so leaving a recording running steadily grew the total.
      final r = TrackRecorder()..start(from: east(0));
      for (var i = 0; i < 200; i++) {
        r.addFix(east(i.isEven ? 1.5 : 0));
      }
      expect(r.distanceMeters, 0);
      expect(r.points, hasLength(1));
    });

    test('the jitter threshold is configurable and honoured exactly', () {
      final r = TrackRecorder(minMoveMeters: 50)..start(from: east(0));
      expect(r.addFix(east(49)), isFalse);
      expect(r.addFix(east(51)), isTrue);
      expect(r.distanceMeters, closeTo(51, 1));
    });

    test('fixes are ignored when not recording', () {
      final r = TrackRecorder();
      expect(r.addFix(east(100)), isFalse);
      expect(r.isRecording, isFalse);
      expect(r.points, isEmpty);
    });

    test('a non-finite fix is rejected', () {
      final r = TrackRecorder()..start(from: east(0));
      expect(r.addFix(const LngLat(double.nan, 44.56)), isFalse);
      expect(r.points, hasLength(1));
    });

    test('stop yields the track and resets', () {
      var now = DateTime.utc(2026, 7, 30, 10);
      final r = TrackRecorder(clock: () => now)..start(from: east(0));
      r.addFix(east(500));
      now = now.add(const Duration(minutes: 12, seconds: 30));

      final track = r.stop(id: 't1')!;
      expect(track.id, 't1');
      expect(track.points, hasLength(2));
      expect(track.distanceMeters, closeTo(500, 1));
      expect(track.elapsed, const Duration(minutes: 12, seconds: 30));
      expect(formatTrackClock(track.elapsed), '12:30');

      expect(r.isRecording, isFalse);
      expect(r.points, isEmpty);
      expect(r.distanceMeters, 0);
    });

    test('an accidental start-then-stop yields no track', () {
      final r = TrackRecorder()..start();
      expect(r.stop(id: 't1'), isNull);

      final oneFix = TrackRecorder()..start(from: east(0));
      expect(
        oneFix.stop(id: 't2'),
        isNull,
        reason: 'a single point is no track',
      );
    });

    test('stopping when never started yields null', () {
      expect(TrackRecorder().stop(id: 't1'), isNull);
    });

    test('elapsed is zero before starting', () {
      expect(TrackRecorder().elapsed, Duration.zero);
    });

    test('restarting clears the previous run', () {
      final r = TrackRecorder()..start(from: east(0));
      r.addFix(east(500));
      r.start(from: east(0));
      expect(r.distanceMeters, 0);
      expect(r.points, hasLength(1));
    });
  });

  group('RecordedTrack JSON', () {
    test('round-trips', () {
      final track = RecordedTrack(
        id: 't1',
        startedAt: DateTime.utc(2026, 7, 30, 10),
        endedAt: DateTime.utc(2026, 7, 30, 10, 45),
        points: const [LngLat(-123.26, 44.56), LngLat(-123.25, 44.57)],
        distanceMeters: 1234.5,
      );
      final back = RecordedTrack.fromJson(track.toJson())!;
      expect(back.id, 't1');
      expect(back.points, track.points);
      expect(back.distanceMeters, 1234.5);
      expect(back.endedAt, track.endedAt);
      expect(back.elapsed, const Duration(minutes: 45));
    });

    test('unusable entries yield null', () {
      expect(RecordedTrack.fromJson(null), isNull);
      expect(RecordedTrack.fromJson(const {}), isNull);
      expect(RecordedTrack.fromJson({'id': 't1'}), isNull);
      expect(
        RecordedTrack.fromJson({'id': 't1', 'startedAt': 'not a date'}),
        isNull,
      );
    });

    test('bad points are dropped without losing the track', () {
      final back = RecordedTrack.fromJson({
        'id': 't1',
        'startedAt': '2026-07-30T10:00:00.000Z',
        'points': [
          [-123.26, 44.56],
          ['x', 'y'],
          [1],
          [-123.25, 44.57],
        ],
        'distanceMeters': 10,
      })!;
      expect(back.points, hasLength(2));
    });
  });
}
