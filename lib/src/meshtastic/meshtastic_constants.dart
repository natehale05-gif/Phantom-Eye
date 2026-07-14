/// Meshtastic BLE GATT UUIDs, cross-validated against the official
/// Python/JS clients and the device firmware's client API docs
/// (https://meshtastic.org/docs/development/device/client-api/) —
/// these are fixed protocol constants, not configurable.
abstract final class MeshtasticBle {
  static const String serviceUuid = '6ba1b218-15a8-461f-9fa8-5dcae273eafd';

  /// Read: yields one `FromRadio` protobuf per read; an empty read means
  /// the device's outbound queue is drained.
  static const String fromRadioCharUuid = '2c55e69e-4993-11ed-b878-0242ac120002';

  /// Write (with response required by firmware): one `ToRadio` protobuf
  /// per write.
  static const String toRadioCharUuid = 'f75c76d2-129e-4dad-a1dd-7866124401e7';

  /// Notify + read: 4-byte counter that increments whenever the device
  /// pushes new data into the `fromradio` queue — subscribe & re-drain
  /// `fromRadioCharUuid` whenever this fires.
  static const String fromNumCharUuid = 'ed9da18c-a800-4f66-a670-aa7547e34453';

  static const int desiredMtu = 512;
}
