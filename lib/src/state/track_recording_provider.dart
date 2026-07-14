import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../models/geo_point.dart';
import '../models/track.dart';
import 'library_providers.dart';

enum RecordingStatus { idle, recording, paused }

class TrackRecordingState {
  const TrackRecordingState({
    this.status = RecordingStatus.idle,
    this.points = const [],
    this.distanceMeters = 0,
    this.elevationGainMeters = 0,
    this.elevationLossMeters = 0,
    this.startedAt,
  });

  final RecordingStatus status;
  final List<TimedPoint> points;
  final double distanceMeters;
  final double elevationGainMeters;
  final double elevationLossMeters;
  final DateTime? startedAt;

  Duration get elapsed =>
      startedAt == null ? Duration.zero : DateTime.now().difference(startedAt!);

  TrackRecordingState copyWith({
    RecordingStatus? status,
    List<TimedPoint>? points,
    double? distanceMeters,
    double? elevationGainMeters,
    double? elevationLossMeters,
    DateTime? startedAt,
  }) {
    return TrackRecordingState(
      status: status ?? this.status,
      points: points ?? this.points,
      distanceMeters: distanceMeters ?? this.distanceMeters,
      elevationGainMeters: elevationGainMeters ?? this.elevationGainMeters,
      elevationLossMeters: elevationLossMeters ?? this.elevationLossMeters,
      startedAt: startedAt ?? this.startedAt,
    );
  }
}

/// onX/Gaia-style breadcrumb track recorder: subscribes to raw GPS fixes
/// while active and accumulates distance/elevation gain/loss live, so the
/// "recording" HUD can show running totals without waiting for a save.
class TrackRecordingNotifier extends Notifier<TrackRecordingState> {
  StreamSubscription<Position>? _sub;

  @override
  TrackRecordingState build() {
    ref.onDispose(() => _sub?.cancel());
    return const TrackRecordingState();
  }

  void start() {
    _sub?.cancel();
    state = TrackRecordingState(status: RecordingStatus.recording, startedAt: DateTime.now());
    _sub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.best, distanceFilter: 3),
    ).listen(_onFix);
  }

  void pause() {
    if (state.status != RecordingStatus.recording) return;
    state = state.copyWith(status: RecordingStatus.paused);
  }

  void resume() {
    if (state.status != RecordingStatus.paused) return;
    state = state.copyWith(status: RecordingStatus.recording);
  }

  void _onFix(Position position) {
    if (state.status != RecordingStatus.recording) return;
    final point = TimedPoint(
      GeoPoint(position.latitude, position.longitude),
      DateTime.now(),
      speedMps: position.speed,
      headingDeg: position.heading,
      elevationMeters: position.altitude,
    );

    var distance = state.distanceMeters;
    var gain = state.elevationGainMeters;
    var loss = state.elevationLossMeters;

    if (state.points.isNotEmpty) {
      final prev = state.points.last;
      distance += GeoMath.distanceMeters(prev.point, point.point);
      final prevEle = prev.elevationMeters;
      final newEle = point.elevationMeters;
      if (prevEle != null && newEle != null) {
        final delta = newEle - prevEle;
        if (delta.abs() >= 1.5) {
          if (delta > 0) {
            gain += delta;
          } else {
            loss += -delta;
          }
        }
      }
    }

    state = state.copyWith(
      points: [...state.points, point],
      distanceMeters: distance,
      elevationGainMeters: gain,
      elevationLossMeters: loss,
    );
  }

  /// Stops recording and saves the track to the library, returning it.
  Future<Track?> stopAndSave(String name) async {
    _sub?.cancel();
    if (state.points.length < 2) {
      state = const TrackRecordingState();
      return null;
    }
    final track = Track(
      name: name,
      points: state.points,
      startedAt: state.startedAt ?? state.points.first.timestamp,
      endedAt: state.points.last.timestamp,
      distanceMeters: state.distanceMeters,
      elevationGainMeters: state.elevationGainMeters,
      elevationLossMeters: state.elevationLossMeters,
    );
    await ref.read(tracksProvider.notifier).add(track);
    state = const TrackRecordingState();
    return track;
  }

  void discard() {
    _sub?.cancel();
    state = const TrackRecordingState();
  }
}

final trackRecordingProvider =
    NotifierProvider<TrackRecordingNotifier, TrackRecordingState>(TrackRecordingNotifier.new);
