# Meshtastic protobuf source

This directory contains a snapshot of the [meshtastic/protobufs](https://github.com/meshtastic/protobufs)
repository, used to generate the Dart bindings in
`lib/src/meshtastic/proto_gen/` via `protoc` + `protoc-gen-dart`.

- Upstream commit: `da2fc413931c81c1d2bc9b6a838d739e2bf35bc1`
- Upstream license: **GPL-3.0** (see `meshtastic-protobufs/LICENSE`)

## ⚠️ Licensing note

The Meshtastic protobuf schema is licensed under GPL-3.0. The generated Dart
code in `lib/src/meshtastic/proto_gen/` is a derivative of that schema. This
is the same reason the official Meshtastic Android/iOS/Web/Python clients are
themselves GPL-3.0 licensed.

**Before shipping Phantom Eye commercially, get a legal opinion on whether
bundling these generated bindings obligates the rest of the app under
GPL-3.0.** Common ways teams route around this:

- License the whole app under GPL-3.0 (what Meshtastic's own official app does).
- Isolate the protobuf decode step into a separate open-source microservice /
  helper process that the closed-source app talks to over a narrow interface.
- Reimplement the tiny subset of the wire format actually needed
  (`Position`, `User`, `NodeInfo`, `MeshPacket`, `FromRadio`/`ToRadio`) from
  the public Meshtastic *protocol documentation* (not the .proto source
  itself) to avoid a direct derivative-work relationship — still get legal
  sign-off, this is not a bulletproof workaround.

This wasn't specified in the app brief, so I made the pragmatic call to use
the real, correct protobufs (rather than guessing field numbers) and flag the
license implication here rather than silently shipping a legal risk.

## Regenerating

```bash
cd tools/meshtastic_proto/meshtastic-protobufs
protoc \
  --dart_out=../../../lib/src/meshtastic/proto_gen \
  --proto_path=. \
  meshtastic/mesh.proto meshtastic/portnums.proto meshtastic/config.proto \
  meshtastic/channel.proto meshtastic/device_ui.proto meshtastic/module_config.proto \
  meshtastic/telemetry.proto meshtastic/xmodem.proto meshtastic/atak.proto \
  meshtastic/connection_status.proto meshtastic/mqtt.proto
```
