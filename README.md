# Phantom Eye

A **native Flutter** app that renders the planet in **photorealistic 3D** —
real buildings *and* terrain — and works both **offline and online**.

Phantom Eye wraps a native, Apple-inspired Cupertino interface around a
CesiumJS rendering surface that streams **Google Photorealistic 3D Tiles**
(photogrammetry: real geometry + imagery for terrain and buildings together)
using your own [Cesium ion](https://ion.cesium.com/) key.

## Why this architecture

Truly *photorealistic* 3D tiles (not gray extruded blocks) are only produced by
Google Photorealistic 3D Tiles / Cesium, which render in WebGL — there is no
native Dart 3D-Tiles renderer. So Phantom Eye is a real, installable Flutter
app (iOS/Android) whose UI, storage, connectivity, and navigation are fully
native, with the globe drawn by a bundled CesiumJS surface bridged over
JavaScript.

- **Native UI** — Cupertino widgets: onboarding, search, destinations rail,
  Photoreal/Terrain segmented control, connectivity pill, cinematic loading.
- **Native storage** — the ion token is kept in the platform keychain/keystore
  via `flutter_secure_storage`.
- **Native connectivity** — `connectivity_plus` drives the online/offline state
  and the WebView cache strategy.
- **Bundled map** — the Cesium engine and app page ship inside the app and are
  served from a local `InAppLocalhostServer`, so the app shell runs with no
  network.

## Offline & online

- **App shell:** fully offline — the Cesium engine and UI are bundled assets.
- **Terrain & buildings:** photoreal tiles stream from Cesium ion / Google when
  online and are cached, so **previously visited areas keep working offline**.
  Fetching *new* areas needs connectivity (photoreal tiles are streamed, and
  Google's 3D Tiles terms restrict permanent offline storage). The app detects
  offline state and serves cached tiles where available.

## Modes

- **Photoreal** — Google Photorealistic 3D Tiles (buildings + terrain).
- **Terrain** — Cesium World Terrain + Cesium OSM Buildings.

## Getting started

```bash
flutter pub get
flutter run           # on a connected iOS/Android device or simulator
```

On first launch, paste your **Cesium ion access token** (free at
<https://ion.cesium.com/tokens>). It's stored securely on-device. You can also
bake one in:

```bash
flutter run --dart-define=CESIUM_ION_TOKEN=your_token_here
```

A stored token always overrides the build-time one.

## Project layout

```
lib/
  main.dart                     # app entry, localhost server, routing
  theme.dart                    # Apple-inspired design tokens + glass panel
  models/ , data/               # Place model + curated destinations
  services/                     # secure token store, connectivity
  map/map_controller.dart       # Flutter <-> Cesium JS bridge
  screens/                      # onboarding + globe screens
webmap/                         # CesiumJS source (Vite + TypeScript)
assets/webmap/                  # built, bundled map (generated; committed)
tool/sync_webmap.sh             # rebuild webmap/ and refresh bundled assets
```

## Updating the bundled map

The web map source lives in `webmap/`. After changing it (or bumping the Cesium
version), regenerate the bundled, offline copy and its asset manifest:

```bash
tool/sync_webmap.sh
```

## Attribution

Google Photorealistic 3D Tiles and Cesium data require on-screen attribution.
The credit line is kept visible at the bottom of the map; please don't remove
it.
