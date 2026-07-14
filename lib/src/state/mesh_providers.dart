import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../meshtastic/meshtastic_ble_service.dart';
import '../meshtastic/meshtastic_repository.dart';
import '../models/mesh_node.dart';

final meshtasticBleServiceProvider = Provider<MeshtasticBleService>((ref) {
  final service = MeshtasticBleService();
  ref.onDispose(service.dispose);
  return service;
});

final meshtasticRepositoryProvider = Provider<MeshtasticRepository>((ref) {
  final repo = MeshtasticRepository(ref.read(meshtasticBleServiceProvider));
  ref.onDispose(repo.dispose);
  return repo;
});

final meshConnectionStateProvider = StreamProvider<MeshConnectionState>((ref) {
  return ref.watch(meshtasticBleServiceProvider).connectionState;
});

/// Live "friends on the mesh" node database, keyed by Meshtastic node
/// number — this is what the map layer and the Mesh tab both watch.
final meshNodesProvider = StreamProvider<Map<int, MeshNode>>((ref) {
  final repo = ref.watch(meshtasticRepositoryProvider);
  return repo.nodes;
});

final meshScanResultsProvider = StreamProvider.autoDispose<List<ScanResult>>((ref) async* {
  // Android 12+ requires runtime BLUETOOTH_SCAN/CONNECT grants; iOS surfaces
  // its own system prompt automatically the first time Core Bluetooth is
  // touched, but requesting explicitly here doesn't hurt and keeps the
  // Android/iOS code paths symmetric. Web has no equivalent permission API
  // — Web Bluetooth prompts per-device inside `navigator.bluetooth.requestDevice()`
  // itself, triggered by flutter_blue_plus_web, so skip this entirely there.
  if (!kIsWeb) {
    await [Permission.bluetoothScan, Permission.bluetoothConnect].request();
  }

  final service = ref.watch(meshtasticBleServiceProvider);
  final controller = StreamController<List<ScanResult>>();
  final sub = service.scan().listen(controller.add);
  ref.onDispose(() {
    sub.cancel();
    service.stopScan();
    controller.close();
  });
  yield* controller.stream;
});
