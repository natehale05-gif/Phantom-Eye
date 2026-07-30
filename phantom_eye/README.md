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

The three pure-Dart packages — the foundation the rest of the app is built on.

| Package | Contents |
|---|---|
| `packages/pe_core` | Geometry (`haversine`, `bearingDeg`, `destinationPoint`, `projectPointOnSegment`, `cumulativeDistances`), `LngLat`/`LatLngBounds`, route / place / weather / location-fix models, `LruCache`, `MinInterval`, `GenerationToken`, `raceForFirstSuccess`, formatters |
| `packages/pe_domain` | `RouteProjector` (windowed), `OffRouteDetector`, `RouteSnapper`, `ArrivalDetector`, `CameraPolicy`, `OpeningHoursParser`, the category registry + `matchCategory`, `DownloadAreaPlanner`, nearby query building + ranking, WMO codes and surf rating |
| `packages/pe_data` | Network clients and response parsers: Overpass (mirror-raced), OSRM, Photon search + reverse, BigDataCloud fallback, Open-Meteo forecast + marine |

`pe_data` keeps every client behind an injected `http.Client` and every
parser as a pure function over decoded JSON, so the whole layer is tested
with `MockClient` and fixtures — no network, no device.

### Why these first

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

All three packages are **Flutter-free and map-engine-free by design.** That is
what makes all of the above headlessly unit-testable — a property the
TypeScript original never had, where these behaviours could realistically
only be checked by driving a car.

## Development

Requires the Dart SDK (3.12+). Flutter is not needed for this layer.

```sh
cd phantom_eye
dart pub get
dart analyze --fatal-infos
(cd packages/pe_core && dart test)
(cd packages/pe_data && dart test)
(cd packages/pe_domain && dart test)
```

`dart test` has to be run per package: the workspace root has no test
directory of its own.

### Legacy parity tests

Three suites check the port against values produced by the **actual legacy
TypeScript** rather than against hand-written expectations, which would
accept a plausible-looking transcription slip just as happily as a correct
port:

| Suite | Fixture generator | Covers |
|---|---|---|
| `pe_domain/test/legacy_parity_test.dart` | `tool/gen_legacy_fixture.mjs` | `bearingDeg`, `haversine`, `formatDistance`, `formatDuration`, windowed `projectOnRoute` |
| `pe_domain/test/categories_test.dart` | `tool/gen_category_fixture.mjs` | the whole category table and `matchCategory` |
| `pe_data/test/routing_parity_test.dart` | `tool/gen_routing_fixture.mjs` | maneuver `classify`/`describe` across 660 cases, plus `parseRoute` leg flattening |

The category and routing generators compile and import the **real**
`src/categories.ts` and `src/routing.ts` through esbuild, so there is no
second copy of those tables to drift. `gen_legacy_fixture.mjs` embeds
verbatim copies of small pure functions instead, and must be kept in sync by
hand when the legacy source changes.

Measured agreement is exact for segment index, along-distance, offset and
every maneuver string; bearings agree to ~1e-9 degrees, the two runtimes
differing only in floating-point operation order.

CI regenerates all three fixtures before running the suites, so divergence
fails the build rather than sitting in a stale committed copy.

```sh
node tool/gen_legacy_fixture.mjs > packages/pe_domain/test/fixtures/legacy_reference.json
node tool/gen_category_fixture.mjs > packages/pe_domain/test/fixtures/category_reference.json
node tool/gen_routing_fixture.mjs > packages/pe_data/test/fixtures/routing_reference.json
```

### Legacy bugs fixed during the port

Each is covered by a test that names the old behaviour:

- **Nearby results deduped by name before sorting.** Every branch of a chain
  collapsed to one row, and the survivor was whichever Overpass emitted
  first — element-id order, not distance. Now sorted first, then deduped by
  OSM identity, with a same-name-within-80 m pass that still collapses the
  one real duplicate (a POI mapped as both a node and its building).
- **`Math.min` over an empty daily array yielded `Infinity`,** collapsing the
  10-day range bars silently. `weekMin`/`weekMax` are now nullable.
- **Weather timestamps were local-naive.** `timezone=auto` returns wall clock
  at the *location*, which both JS and Dart read as *device* time — so a
  Tokyo forecast viewed from California was labelled hours wrong. The
  response's `utc_offset_seconds` is now captured and applied.
- **UV and visibility read the previous hour** on the hour, and by the
  device/location zone difference otherwise.
- **Current swell fell back to nothing,** rendering `NaN ft` at spots whose
  marine model omits the swell fields; it now falls back to the wave figures
  exactly as the hourly values already did.

## Not yet built

`pe_map` and its engine adapters, `pe_ui`, and the Flutter app
itself. Per the plan, the next gate is **Phase 0** — a throwaway spike that
empirically settles the engine/platform matrix (notably whether Flutter
widgets composite correctly over the map on Windows and macOS, what Linux
can actually support, and whether photoreal mode is thermally viable on
phones) before any of that is committed to.
