import 'geo_point.dart';

/// A node ("friend") seen on the Meshtastic mesh, built up from
/// `NodeInfo`/`Position`/`User` protobuf packets received over BLE.
class MeshNode {
  const MeshNode({
    required this.nodeNum,
    this.longName,
    this.shortName,
    this.point,
    this.altitudeMeters,
    this.batteryPercent,
    this.voltage,
    this.snr,
    this.lastHeard,
    this.isSelf = false,
  });

  /// Meshtastic's 32-bit node identifier (`User.id` decodes to
  /// `!<hex nodeNum>`).
  final int nodeNum;
  final String? longName;
  final String? shortName;
  final GeoPoint? point;
  final double? altitudeMeters;
  final int? batteryPercent;
  final double? voltage;
  final double? snr;
  final DateTime? lastHeard;
  final bool isSelf;

  String get displayName =>
      longName ?? shortName ?? '!${nodeNum.toRadixString(16).padLeft(8, '0')}';

  String get idHex => '!${nodeNum.toRadixString(16).padLeft(8, '0')}';

  MeshNode mergeWith(MeshNode update) {
    return MeshNode(
      nodeNum: nodeNum,
      longName: update.longName ?? longName,
      shortName: update.shortName ?? shortName,
      point: update.point ?? point,
      altitudeMeters: update.altitudeMeters ?? altitudeMeters,
      batteryPercent: update.batteryPercent ?? batteryPercent,
      voltage: update.voltage ?? voltage,
      snr: update.snr ?? snr,
      lastHeard: update.lastHeard ?? lastHeard,
      isSelf: update.isSelf || isSelf,
    );
  }
}
