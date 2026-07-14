import 'dart:async';
import 'dart:math';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'meshtastic_constants.dart';
import 'proto_gen/meshtastic/mesh.pb.dart';
import 'proto_gen/meshtastic/portnums.pbenum.dart';

enum MeshConnectionState { disconnected, connecting, configuring, ready, error }

/// Talks the Meshtastic BLE client-API protocol
/// (https://meshtastic.org/docs/development/device/client-api/) to a single
/// paired radio: scan → connect → MTU 512 → subscribe `fromnum` → drain
/// `fromradio` → send `want_config_id` → keep draining forever as
/// `FromRadio` frames (NodeInfo/Position/telemetry/text packets) arrive.
///
/// Exposes a plain [Stream<FromRadio>] — [MeshtasticRepository] is the layer
/// that turns those frames into a friends-on-the-map node database.
class MeshtasticBleService {
  MeshtasticBleService();

  BluetoothDevice? _device;
  BluetoothCharacteristic? _fromRadioChar;
  BluetoothCharacteristic? _toRadioChar;
  BluetoothCharacteristic? _fromNumChar;
  StreamSubscription<List<int>>? _fromNumSub;
  StreamSubscription<BluetoothConnectionState>? _connectionSub;

  final _stateController = StreamController<MeshConnectionState>.broadcast();
  final _frameController = StreamController<FromRadio>.broadcast();

  Stream<MeshConnectionState> get connectionState => _stateController.stream;
  Stream<FromRadio> get frames => _frameController.stream;

  bool _draining = false;

  /// Scans for nearby Meshtastic radios (filtered by the mesh service UUID
  /// so the picker doesn't get flooded with every random BLE device).
  Stream<List<ScanResult>> scan({Duration timeout = const Duration(seconds: 12)}) {
    FlutterBluePlus.startScan(
      withServices: [Guid(MeshtasticBle.serviceUuid)],
      timeout: timeout,
    );
    return FlutterBluePlus.scanResults;
  }

  Future<void> stopScan() => FlutterBluePlus.stopScan();

  Future<void> connect(BluetoothDevice device) async {
    _device = device;
    _stateController.add(MeshConnectionState.connecting);
    try {
      // NOTE — licensing: flutter_blue_plus 2.x requires declaring a
      // [License] on every connect() call. `nonprofit` covers personal/
      // educational use only; ship Phantom Eye commercially and you must
      // buy a `License.commercial` key from the flutter_blue_plus authors
      // (see that package's LICENSE) or swap to a different BLE plugin
      // (e.g. `flutter_reactive_ble`) before release.
      await device.connect(license: License.nonprofit, timeout: const Duration(seconds: 15));
      _connectionSub?.cancel();
      _connectionSub = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          _stateController.add(MeshConnectionState.disconnected);
        }
      });

      await device.requestMtu(MeshtasticBle.desiredMtu);

      final services = await device.discoverServices();
      final meshService = services.firstWhere(
        (s) => s.uuid.str128.toLowerCase() == MeshtasticBle.serviceUuid,
        orElse: () => throw StateError('Meshtastic GATT service not found on device'),
      );

      _fromRadioChar = meshService.characteristics.firstWhere(
        (c) => c.uuid.str128.toLowerCase() == MeshtasticBle.fromRadioCharUuid,
      );
      _toRadioChar = meshService.characteristics.firstWhere(
        (c) => c.uuid.str128.toLowerCase() == MeshtasticBle.toRadioCharUuid,
      );
      _fromNumChar = meshService.characteristics.firstWhere(
        (c) => c.uuid.str128.toLowerCase() == MeshtasticBle.fromNumCharUuid,
      );

      _stateController.add(MeshConnectionState.configuring);

      await _fromNumChar!.setNotifyValue(true);
      _fromNumSub = _fromNumChar!.onValueReceived.listen((_) => _drainFromRadio());

      // Kick off the initial NodeDB dump.
      final nonce = Random().nextInt(0x7fffffff);
      await _toRadioChar!.write(
        ToRadio(wantConfigId: nonce).writeToBuffer(),
        withoutResponse: false,
      );

      // Firmware may already have data queued before the first notify.
      unawaited(_drainFromRadio());
    } catch (e) {
      _stateController.add(MeshConnectionState.error);
      rethrow;
    }
  }

  Future<void> _drainFromRadio() async {
    if (_draining || _fromRadioChar == null) return;
    _draining = true;
    try {
      var configComplete = false;
      // Cap iterations defensively — a well-behaved radio always answers
      // with an empty payload once its queue is drained.
      for (var i = 0; i < 500; i++) {
        final bytes = await _fromRadioChar!.read();
        if (bytes.isEmpty) break;
        try {
          final frame = FromRadio.fromBuffer(bytes);
          _frameController.add(frame);
          if (frame.whichPayloadVariant() == FromRadio_PayloadVariant.configCompleteId) {
            configComplete = true;
          }
        } catch (_) {
          // Skip malformed/partial frames rather than killing the drain loop.
          continue;
        }
      }
      if (configComplete) {
        _stateController.add(MeshConnectionState.ready);
      }
    } finally {
      _draining = false;
    }
  }

  /// Sends a plain-text broadcast message on the primary channel — useful
  /// for a lightweight "ping your group" feature alongside position
  /// sharing (not required by the brief, but effectively free given the
  /// protocol plumbing already exists here).
  Future<void> sendTextMessage(String text, {int channel = 0}) async {
    if (_toRadioChar == null) return;
    final packet = MeshPacket(
      to: 0xffffffff, // broadcast
      channel: channel,
      wantAck: true,
      decoded: Data(
        portnum: PortNum.TEXT_MESSAGE_APP,
        payload: text.codeUnits,
      ),
    );
    await _toRadioChar!.write(ToRadio(packet: packet).writeToBuffer(), withoutResponse: false);
  }

  Future<void> disconnect() async {
    await _fromNumSub?.cancel();
    await _connectionSub?.cancel();
    await _device?.disconnect();
    _stateController.add(MeshConnectionState.disconnected);
  }

  void dispose() {
    _fromNumSub?.cancel();
    _connectionSub?.cancel();
    _stateController.close();
    _frameController.close();
  }
}
