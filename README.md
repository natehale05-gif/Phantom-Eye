# Phantom Eye

A photorealistic 3D globe explorer, designed to feel like Apple made it.

Phantom Eye renders the planet with **Google Photorealistic 3D Tiles** (real
buildings **and** terrain from photogrammetry) streamed through
[CesiumJS](https://cesium.com/platform/cesiumjs/) and your own
[Cesium ion](https://ion.cesium.com/) key. Search anywhere on Earth, glide
between iconic destinations, or drop into a Cesium World Terrain + OSM Buildings
view.

## Highlights

- **Photoreal everywhere** — Google Photorealistic 3D Tiles: real geometry and
  imagery for both terrain and buildings, in one seamless mesh.
- **Terrain mode** — toggle to Cesium World Terrain with Cesium OSM Buildings.
- **Search the planet** — Cesium ion geocoding with cinematic fly-to arrivals.
- **Curated destinations** — hand-framed hero shots of iconic places.
- **Apple-grade UI** — frosted glass, SF-style typography, spring animations,
  and a calm, cinematic dark scene.
- **Bring your own key** — enter your Cesium ion token once and it's remembered
  locally, or bake it in at build time.

## Getting started

```bash
npm install
npm run dev
```

Open the printed URL. On first launch you'll be asked for a **Cesium ion access
token** — grab a free one at <https://ion.cesium.com/tokens>. It's stored in
your browser's `localStorage` and never leaves your machine.

### Baking the token at build time (optional)

```bash
cp .env.example .env
# set VITE_CESIUM_ION_TOKEN=your_token_here
npm run build
```

A runtime-entered token always overrides the build-time value, so you can still
switch keys without rebuilding.

## Scripts

| Command           | Description                          |
| ----------------- | ------------------------------------ |
| `npm run dev`     | Start the Vite dev server            |
| `npm run build`   | Type-check and build for production  |
| `npm run preview` | Preview the production build locally |

## Tech

- [CesiumJS](https://cesium.com/platform/cesiumjs/) + Cesium ion assets
  (Google Photorealistic 3D Tiles, World Terrain, OSM Buildings)
- [Vite](https://vitejs.dev/) + TypeScript

## Attribution

Google Photorealistic 3D Tiles and Cesium data require on-screen attribution.
Phantom Eye keeps the Cesium credit display visible in the lower-left corner;
please don't remove it.
