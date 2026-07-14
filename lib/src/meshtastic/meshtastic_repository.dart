import 'dart:async';

import '../models/geo_point.dart';
import '../models/mesh_node.dart';
import 'meshtastic_ble_service.dart';
import 'proto_gen/meshtastic/mesh.pb.dart';
import 'proto_gen/meshtastic/portnums.pbenum.dart';
import 'proto_gen/meshtastic/telemetry.pb.dart';

/// Builds and maintains the "friends on the mesh" node database by decoding
/// `FromRadio` frames: the initial `nodeInfo` dump (NodeDB) gives us
/// everyone the radio already knows about, and live `MeshPacket`s with
/// `POSITION_APP`/`NODEINFO_APP`/`TELEMETRY_APP` payloads keep it fresh as
/// people move.
class MeshtasticRepository {
  MeshtasticRepository(this._ble) {
    _subscription = _ble.frames.listen(_handleFrame);
  }

  final MeshtasticBleService _ble;
  StreamSubscription<FromRadio>? _subscription;

  final Map<int, MeshNode> _nodes = {};
  final _nodesController = StreamController<Map<int, MeshNode>>.broadcast();

  int? _myNodeNum;

  Stream<Map<int, MeshNode>> get nodes => _nodesController.stream;
  Map<int, MeshNode> get currentNodes => Map.unmodifiable(_nodes);

  void _handleFrame(FromRadio frame) {
    switch (frame.whichPayloadVariant()) {
      case FromRadio_PayloadVariant.myInfo:
        _myNodeNum = frame.myInfo.myNodeNum;
        break;
      case FromRadio_PayloadVariant.nodeInfo:
        _upsertFromNodeInfo(frame.nodeInfo);
        break;
      case FromRadio_PayloadVariant.packet:
        _handleMeshPacket(frame.packet);
        break;
      default:
        break;
    }
  }

  void _upsertFromNodeInfo(NodeInfo info) {
    final update = MeshNode(
      nodeNum: info.num,
      longName: info.hasUser() && info.user.longName.isNotEmpty ? info.user.longName : null,
      shortName: info.hasUser() && info.user.shortName.isNotEmpty ? info.user.shortName : null,
      point: info.hasPosition() && info.position.latitudeI != 0
          ? GeoPoint(info.position.latitudeI * 1e-7, info.position.longitudeI * 1e-7)
          : null,
      altitudeMeters: info.hasPosition() ? info.position.altitude.toDouble() : null,
      batteryPercent: info.hasDeviceMetrics() ? info.deviceMetrics.batteryLevel : null,
      voltage: info.hasDeviceMetrics() ? info.deviceMetrics.voltage.toDouble() : null,
      snr: info.snr.toDouble(),
      lastHeard: info.lastHeard > 0
          ? DateTime.fromMillisecondsSinceEpoch(info.lastHeard * 1000)
          : null,
      isSelf: _myNodeNum != null && info.num == _myNodeNum,
    );
    _merge(update);
  }

  void _handleMeshPacket(MeshPacket packet) {
    if (packet.whichPayloadVariant() != MeshPacket_PayloadVariant.decoded) {
      return; // encrypted packet we can't read without channel keys
    }
    final data = packet.decoded;
    final now = DateTime.now();

    switch (data.portnum) {
      case PortNum.POSITION_APP:
        try {
          final position = Position.fromBuffer(data.payload);
          if (position.latitudeI == 0 && position.longitudeI == 0) return;
          _merge(
            MeshNode(
              nodeNum: packet.from,
              point: GeoPoint(position.latitudeI * 1e-7, position.longitudeI * 1e-7),
              altitudeMeters: position.altitude.toDouble(),
              lastHeard: now,
              snr: packet.rxSnr.toDouble(),
              isSelf: _myNodeNum != null && packet.from == _myNodeNum,
            ),
          );
        } catch (_) {
          // Ignore malformed payloads rather than crashing the drain loop.
        }
        break;
      case PortNum.NODEINFO_APP:
        try {
          final user = User.fromBuffer(data.payload);
          _merge(
            MeshNode(
              nodeNum: packet.from,
              longName: user.longName.isNotEmpty ? user.longName : null,
              shortName: user.shortName.isNotEmpty ? user.shortName : null,
              lastHeard: now,
              snr: packet.rxSnr.toDouble(),
              isSelf: _myNodeNum != null && packet.from == _myNodeNum,
            ),
          );
        } catch (_) {}
        break;
      case PortNum.TELEMETRY_APP:
        // Device telemetry payload — battery % in particular is handy to
        // surface next to a friend's name on the map.
        try {
          final telemetry = Telemetry.fromBuffer(data.payload);
          _merge(
            MeshNode(
              nodeNum: packet.from,
              batteryPercent: telemetry.hasDeviceMetrics() ? telemetry.deviceMetrics.batteryLevel : null,
              voltage: telemetry.hasDeviceMetrics() ? telemetry.deviceMetrics.voltage.toDouble() : null,
              lastHeard: now,
              snr: packet.rxSnr.toDouble(),
              isSelf: _myNodeNum != null && packet.from == _myNodeNum,
            ),
          );
        } catch (_) {}
        break;
      default:
        // Text messages and everything else don't affect node state.
        break;
    }
  }

  void _merge(MeshNode update) {
    final existing = _nodes[update.nodeNum];
    _nodes[update.nodeNum] = existing == null ? update : existing.mergeWith(update);
    _nodesController.add(currentNodes);
  }

  void dispose() {
    _subscription?.cancel();
    _nodesController.close();
  }
}
