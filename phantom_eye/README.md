# Phantom Eye — Flutter rewrite

Cross-platform rebuild of Phantom Eye targeting Windows, macOS, Linux,
Android, iOS and PWA, with a hybrid map engine: MapLibre as the fast native
default, plus an opt-in photorealistic mode backed by CesiumJS in a WebView.

The full plan — engine/platform matrix, de-risking spikes, phased port,
packaging and distribution — lives outside this directory in the approved
project plan. This README covers only what exists today.

> The legacy CesiumJS web app in the repository root is **still the shipping
> product** and continues to deploy to GitHub Pages. Nothing here replaces it
> until the port reaches feature parity.

## What exists today

The two pure-Dart packages — the foundation the rest of the app is built on.

| Package | Contents |
|---|---|
| `packages/pe_core` | Geometry (`haversine`, `bearingDeg`, `destinationPoint`, `projectPointOnSegment`, `cumulativeDistances`), `LngLat`/`LatLngBounds`, route + location-fix models, `LruCache`, `MinInterval`, `GenerationToken`, formatters |
| `packages/pe_domain` | `RouteProjector` (windowed), `OffRouteDetector`, `RouteSnapper`, `ArrivalDetector`, `CameraPolicy` |

### Why these two first

They hold the app's genuinely hard-won behaviour — the parts that took real
debugging and must not be casually re-derived:

- **Windowed route projection.** A long route holds thousands of vertices;
  rescanning all of them on every GPS fix was a measurable cost. The
  projector searches ±40 segments around the previous match instead, and
  `reset()` on route change is what keeps that safe.
- **Sustained-deviation rerouting.** A wrong turn must be distinguished from
  a noisy fix: 55 m off-route, sustained 3 s, with a 5 s cooldown and an
  in-flight guard. Arrival suppresses it entirely.
- **Route snapping.** The *route* bends to your position and trims what is
  behind you — deliberately not the puck snapping to the road, which was
  tried and reverted because it made the dot lie about where you were.
- **Camera throttling.** `CameraPolicy`'s 800 ms follow re-aim was the fix
  for the phone-overheating problem: every re-aim forces the tile engine to
  re-cull and re-stream. The 0.6 s **linear** chase glide is equally
  deliberate — eased curves decelerate into each target and visibly stutter
  when the next fix arrives mid-flight.

Both packages are **Flutter-free and map-engine-free by design.** That is
what makes all of the above headlessly unit-testable — a property the
TypeScript original never had, where these behaviours could realistically
only be checked by driving a car.

## Development

Requires the Dart SDK (3.12+). Flutter is not needed for this layer.

```sh
cd phantom_eye
dart pub get
dart analyze
(cd packages/pe_core && dart test)
(cd packages/pe_domain && dart test)
```

### Legacy parity tests

`packages/pe_domain/test/legacy_parity_test.dart` checks the port against
values produced by the **actual legacy TypeScript**, embedded verbatim in
`tool/gen_legacy_fixture.mjs`. Running both over identical inputs and
demanding agreement catches transcription slips that a plausible-looking
hand-written expectation would accept.

Measured agreement is exact for segment index, along-distance and offset;
bearings agree to ~1e-9 degrees, the two runtimes differing only in
floating-point operation order.

Regenerate the fixture after any change to the legacy source it mirrors:

```sh
node tool/gen_legacy_fixture.mjs > packages/pe_domain/test/fixtures/legacy_reference.json
```

## Not yet built

`pe_data`, `pe_map` and its engine adapters, `pe_ui`, and the Flutter app
itself. Per the plan, the next gate is **Phase 0** — a throwaway spike that
empirically settles the engine/platform matrix (notably whether Flutter
widgets composite correctly over the map on Windows and macOS, what Linux
can actually support, and whether photoreal mode is thermally viable on
phones) before any of that is committed to.
