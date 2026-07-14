# Phantom Eye

A cross-platform Flutter (iOS + Android, CarPlay + Android Auto) maps app
that's trying to do two jobs at once:

1. **Everyday navigation** — a clean, Apple-feeling turn-by-turn driving /
   walking / biking app (an Apple Maps alternative).
2. **Offroad / backcountry** — topo basemaps, trail routing, track
   recording, waypoints, and a custom route builder (an onX Offroad /
   Gaia GPS / Backcountry-style tool).

Plus a third pillar bolted on top: **Meshtastic** BLE integration to see
where your friends are, off-grid.

There was no design handoff for this build — see [Design notes](#design-notes)
for how the UI/architecture decisions were made instead.

## Quick start

```bash
flutter pub get
flutter run          # or: flutter build apk / flutter build ios / flutter build web
flutter test         # unit tests for the geo/routing/nav math
```

Requires Flutter 3.44+ (this repo was built and verified against it — see
[Environment](#environment-this-was-built--verified-against)).

## Testing it yourself without Xcode/Android Studio: the web build

There's no Xcode/Android SDK required to try Phantom Eye — every push to
`main` (and to any `cursor/**` branch) auto-deploys a web build to **GitHub
Pages** via `.github/workflows/deploy-web.yml`.

**One-time setup (you, not me — I can't toggle repo settings):** in this
repo's GitHub Settings → Pages, set **Source: GitHub Actions**. After that,
the workflow runs automatically on every push and the site shows up at
`https://<your-github-username>.github.io/<repo-name>/`. You can also
trigger it manually from the Actions tab (`Deploy web build to GitHub
Pages` → *Run workflow*) if you want a build sooner than the next push.

Locally, the same build is just:

```bash
flutter build web --release --base-href "/Phantom-Eye/"
# then serve build/web/ with any static file server, e.g.:
cd build/web && python3 -m http.server 8080
```

### Web build caveats (read before assuming something's "broken")

The web build is for **UI/UX QA in a browser**, not a third platform target
in its own right:

- **Meshtastic (BLE)** only works in browsers with Web Bluetooth support
  (Chrome/Edge on desktop & Android; **not** Safari/Firefox, and not iOS
  Safari at all) and needs the browser's own device-picker permission
  prompt — there's no equivalent of a native pairing flow.
- **CarPlay / Android Auto** don't exist on the web, obviously — those
  panels/screens simply aren't reachable from the app's normal navigation.
- **Location** requires a secure context (HTTPS or localhost) — GitHub
  Pages serves HTTPS, so this works there and when testing over
  `http://localhost`, but will silently fail over plain `http://<lan-ip>`.
- Map tiles/weather/routing/geocoding calls all go through the same public
  demo APIs as the mobile build (see below) — same rate limits apply.
- Local storage (tracks/routes/waypoints/settings) uses the browser's
  `localStorage` via `shared_preferences_web` — clearing site data/using a
  different browser resets it, same as any other web app.

## Architecture

- **State management: Riverpod (no code generation).** Chosen over Bloc
  because this app leans heavily on async data (weather, search, routing,
  elevation, BLE streams) where `AsyncNotifier`/`StreamProvider`/`FutureProvider`
  map directly onto the problem, and because skipping `riverpod_generator`
  keeps the build free of a `build_runner` step — one less moving part for
  a project already juggling protobuf codegen (see below).
- **Map engine: MapLibre Native (`maplibre_gl`)**, not a WebView. Since
  there was no design handoff mandating Cesium/WebView, and the ask
  shifted to "build from scratch," a native vector/raster map SDK is the
  more idiomatic Flutter choice: better performance, native gesture
  handling, and no JS bridge to maintain. Map tiles are raster (OSM /
  OpenTopoMap / Esri) rather than vector — see
  `lib/src/features/map/map_styles.dart` for why, and the
  [production checklist](#before-you-ship-this) for what to swap.
- **No Material widgets in the UI layer** — deliberately Cupertino-flavored
  custom widgets (`lib/src/widgets/glass_surface.dart` etc.) built on
  `BackdropFilter` for the "feels like an Apple product" ask, on both iOS
  and Android.
- **Folder layout:**
  ```
  lib/src/
    theme/         design tokens (colors, type, spacing) + ThemeData
    core/          geo math, polyline codec, networking, local/file storage
    models/        plain Dart value types (no codegen)
    services/      geocoding, weather, routing, elevation, GPX, nav engine
    state/         Riverpod providers
    features/      one folder per screen/feature
    meshtastic/    BLE service + repository + generated protobufs
    platform/      Dart-side CarPlay / Android Auto bridges
  android/app/.../carapp/   Android Auto CarAppService (Kotlin)
  ios/Runner/CarPlay/       CarPlay scene delegate (Swift, see caveat below)
  ```

## Third-party services (all free, keyless, **demo-tier**)

| Purpose | Service | Notes |
|---|---|---|
| Geocoding / search | [Photon](https://photon.komoot.io) | OSM-based, no key |
| Routing (drive/walk/bike) | [Valhalla](https://valhalla.openstreetmap.de) → [OSRM](https://router.project-osrm.org) → straight-line | Fallback chain, see `routing_service.dart` |
| Weather + elevation | [Open-Meteo](https://open-meteo.com) | No key, generous free tier |
| Streets tiles | OpenStreetMap raster | Standard attribution required |
| Topo tiles | [OpenTopoMap](https://opentopomap.org) | Read their usage policy before real traffic |
| Satellite + hillshade | Esri World Imagery / Hillshade | Free tier, no key |

**Every one of these is explicitly a public demo instance not meant for
production load.** See [Before you ship this](#before-you-ship-this).

## The Meshtastic integration

`lib/src/meshtastic/` implements the real BLE GATT protocol
(`6ba1b218-...` service, `fromradio`/`toradio`/`fromnum` characteristics —
verified against the official client-API docs and Python/JS clients, not
guessed) and decodes real Meshtastic protobufs (`NodeInfo`, `Position`,
`User`, `Telemetry`) generated with `protoc` from the actual
`meshtastic/protobufs` schema — see `tools/meshtastic_proto/`.

**⚠️ Two licensing flags that need a decision before shipping:**

1. The Meshtastic protobuf schema is **GPL-3.0**. The generated Dart
   bindings in `lib/src/meshtastic/proto_gen/` are a derivative of that
   schema — this is why Meshtastic's own official apps are GPL-3.0. Get a
   legal opinion on whether this drags the rest of Phantom Eye under
   GPL-3.0 too. Details/options: `tools/meshtastic_proto/README.md`.
2. `flutter_blue_plus` (the BLE plugin) requires declaring a `License` on
   every connect call; this build uses `License.nonprofit`, which is **not**
   valid for a commercial release — that requires purchasing
   `License.commercial` from the plugin's authors, or swapping to a
   different BLE plugin (e.g. `flutter_reactive_ble`). See the comment in
   `lib/src/meshtastic/meshtastic_ble_service.dart`.

## CarPlay / Android Auto status

- **Android Auto**: a real, compiling `CarAppService` + `NavigationTemplate`
  implementation lives in `android/app/src/main/kotlin/.../carapp/`. It
  draws a hand-rolled Canvas map (route line + puck) into the surface the
  host provides — not the full MapLibre renderer (that would mean running
  a second live MapLibre GL context outside Flutter's engine; a bigger,
  separately-scoped project). This has been built and verified against a
  real Android SDK/Gradle toolchain in this environment.
- **CarPlay**: `ios/Runner/CarPlay/` has an equivalent Swift draft
  (`CPTemplateApplicationSceneDelegate` + `CPMapTemplate` + hand-drawn map),
  but **this environment has no macOS/Xcode, so it has never been
  compiled.** Per the brief: *"flag if you hit the CarPlay navigation-app
  entitlement requirement so I can sort that out"* — you will hit it. CarPlay
  navigation apps require Apple to manually grant the
  `com.apple.developer.carplay-maps` entitlement (a Developer Portal
  request, not a code change), and someone needs to open this in Xcode,
  add the CarPlay files to the `Runner` target (the project isn't using
  Xcode 16's filesystem-synced groups, so dropped-in files aren't
  auto-included), and fix whatever the compiler flags. Full details:
  `ios/Runner/CarPlay/README.md`.

## Design notes

No design handoff existed for this build (the original brief referenced a
`design_handoff_phantom_eye/` package that was never present in the repo).
Every visual/UX decision — color palette, type scale, spacing, screen
layouts, iconography — was made from scratch to read as a modern,
Apple-feeling app:

- **Font**: bundled `Inter` (SIL OFL, `assets/fonts/`) rather than SF Pro
  — SF Pro's license doesn't clearly cover non-Apple-platform bundling,
  and it isn't installed on Android anyway. Inter is a common, freely
  licensed stand-in with very similar geometry.
- **Two accent palettes**: iOS-blue for "Everyday" mode, burnt-orange/olive
  for "Offroad" mode — swapped via `AppMode` in
  `lib/src/theme/app_theme.dart`.
- **Land ownership boundaries / hunting units** (a core onX Hunt feature)
  are **not implemented** — there's no free, open, nationwide data source
  for this; it needs a licensed GIS feed (BLM/USFS parcel data, state
  game-department feeds, or a paid provider). The Settings screen has a
  disabled placeholder row explaining this rather than faking data.

## Environment this was built & verified against

- Flutter **3.44.6** (stable), Dart 3.12.2
- Android: SDK platform 36, build-tools 36, NDK 28.1.13356709, AGP 8.13.0,
  Gradle 8.14.2, Kotlin 2.2.20, `minSdk 24`
- `flutter analyze` — no issues
- `flutter test` — all unit tests pass (geo math, polyline codec, nav
  engine, formatters)
- `flutter build apk --debug` — builds successfully, including the
  Android Auto Kotlin module
- `flutter build web --release` — builds successfully; smoke-tested by
  serving the output and loading it in headless Chrome (mounted correctly,
  no fatal boot errors visible in `stderr`/DOM)
- iOS/CarPlay: **not built or run** — no macOS available in this
  environment. Needs verification in Xcode.

## Before you ship this

1. Stand up your own Photon / Valhalla / OSRM instances (or pay for a
   provider — Mapbox, Stadia Maps, Geoapify, etc.) and swap
   `lib/src/core/network/endpoints.dart`.
2. Consider self-hosting tiles, or a paid vector-tile provider for a
   nicer-looking basemap than the current raster tiles.
3. Resolve the Meshtastic GPL-3.0 and flutter_blue_plus commercial-license
   questions above.
4. Get the CarPlay entitlement from Apple and finish/verify
   `ios/Runner/CarPlay/` in Xcode.
5. Source a licensed land-ownership/hunting-unit GIS feed if that's a
   must-have for parity with onX Hunt.
6. Tighten `HostValidator.ALLOW_ALL_HOSTS_VALIDATOR` in
   `PhantomEyeCarAppService.kt` to an actual allowlist.
7. Add a real signing config for Android release builds (currently signs
   release with the debug keystore, per the Flutter template default).
