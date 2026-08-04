import 'package:pe_core/pe_core.dart';

/// The elapsed-time readout on the recording HUD.
///
/// Ported from `clock` in `src/field.ts:462`. Hours are shown only once there
/// are any, so a short walk reads `7:42` rather than `0:07:42`, and the
/// minute field is zero-padded only in the hour form — matching the original
/// exactly, since this string sits in the HUD next to the distance.
String formatTrackClock(Duration elapsed) {
  final total = elapsed.inSeconds;
  if (total <= 0) return '0:00';
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  String pad(int n) => n.toString().padLeft(2, '0');
  return h > 0 ? '$h:${pad(m)}:${pad(s)}' : '$m:${pad(s)}';
}

/// Accumulates a GPS track while recording.
///
/// Ported from the recording half of `src/field.ts` (`startRecording`,
/// `stopRecording`, and the `recordDistance` accumulation at line 138).
///
/// Distance is summed between consecutive accepted fixes rather than computed
/// from the whole line at the end, so the HUD can show it live. [minMoveMeters]
/// is the one addition: a stationary phone emits fixes that jitter by several
/// metres, and the original summed every one of them, so leaving a recording
/// running while parked steadily inflated the distance. Points closer than
/// the threshold are ignored — which also keeps the stored geometry from
/// filling with noise.
final class TrackRecorder {
  TrackRecorder({
    this.minMoveMeters = kTrackMinMoveMeters,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// Fixes closer than this to the previous point are treated as jitter.
  final double minMoveMeters;

  final DateTime Function() _clock;

  final List<LngLat> _points = [];
  DateTime? _startedAt;
  double _distanceMeters = 0;

  bool get isRecording => _startedAt != null;

  /// Metres travelled so far.
  double get distanceMeters => _distanceMeters;

  /// Points accepted so far, in order.
  List<LngLat> get points => List.unmodifiable(_points);

  /// Time since [start], or zero when not recording.
  Duration get elapsed {
    final startedAt = _startedAt;
    return startedAt == null ? Duration.zero : _clock().difference(startedAt);
  }

  /// Begin a recording, optionally seeded with the current position.
  ///
  /// Seeding matters: without it the first leg of the track is missing,
  /// because the first fix after starting only establishes the origin.
  void start({LngLat? from}) {
    _points.clear();
    _distanceMeters = 0;
    _startedAt = _clock();
    if (from != null && from.isFinite) _points.add(from);
  }

  /// Offer a fix to the recording. Returns true if it was accepted.
  bool addFix(LngLat position) {
    if (!isRecording || !position.isFinite) return false;
    if (_points.isEmpty) {
      _points.add(position);
      return true;
    }
    final moved = haversine(_points.last, position);
    if (moved < minMoveMeters) return false;
    _distanceMeters += moved;
    _points.add(position);
    return true;
  }

  /// Finish the recording and hand back the track.
  ///
  /// Returns null if nothing was recorded, so an accidental start-then-stop
  /// does not litter the track list with an empty entry.
  RecordedTrack? stop({required String id}) {
    final startedAt = _startedAt;
    _startedAt = null;
    if (startedAt == null || _points.length < 2) {
      _points.clear();
      _distanceMeters = 0;
      return null;
    }
    final track = RecordedTrack(
      id: id,
      startedAt: startedAt,
      endedAt: _clock(),
      points: List.of(_points),
      distanceMeters: _distanceMeters,
    );
    _points.clear();
    _distanceMeters = 0;
    return track;
  }
}

/// Movement below this between fixes is treated as GPS jitter.
///
/// Sized just above the noise of a stationary consumer GPS (typically 2–4 m)
/// and well below any real walking pace between fixes.
const double kTrackMinMoveMeters = 5;
