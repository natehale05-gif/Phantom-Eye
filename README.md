# Phantom Eye

A photorealistic 3D globe explorer, designed to feel like Apple made it.

Phantom Eye renders the planet with **Google Photorealistic 3D Tiles** (real
buildings **and** terrain from photogrammetry) streamed through
[CesiumJS](https://cesium.com/platform/cesiumjs/) and your own
[Cesium ion](https://ion.cesium.com/) key. Search anywhere on Earth, glide
between iconic destinations, jump to your location, or get driving directions
with turn-by-turn guidance played out across the 3D globe.

## Highlights

- **Photoreal everywhere** — Google Photorealistic 3D Tiles: real geometry and
  imagery for both terrain and buildings, in one seamless mesh. No mode toggle,
  no compromises.
- **Turn-by-turn navigation** — search a place, tap the directions arrow, and
  Phantom Eye draws the route on the globe, lists every maneuver with distances,
  and flies a guided fly-through with a live turn banner.
- **Live location + follow camera** — an Apple-style blue dot with an accuracy
  ring, clamped to the photoreal surface. Tap it to enter a chase camera that
  looks at and follows you as you move.
- **Waypoints** — drop, name, list, fly to, delete, and route to saved points.
  Persisted locally for offroad/hunt/backcountry marks.
- **Track recording** — record a breadcrumb trail on the globe with a live
  distance + elapsed-time readout.
- **Coordinate + elevation HUD** — always know exactly where you are.
- **Opens at your location** — on launch it flies to and follows your GPS
  position (falling back to a hero view if location is unavailable).
- **Search the planet** — Cesium ion geocoding with cinematic fly-to arrivals.
- **Tools menu** — every function (location, waypoints, recording, whole-planet)
  lives in one Apple-style dropdown beside the search bar.
- **Apple-grade UI** — frosted glass, SF-style typography, spring animations,
  and a calm, cinematic dark scene.
- **Bring your own key** — enter your Cesium ion token once and it's remembered
  locally, or bake it in at build time.

Routing is powered by the free, rate-limited
[OSRM](https://project-osrm.org/) demo server (no key required). Swap in a keyed
provider in `src/routing.ts` for production traffic.

## Test it live (GitHub Pages)

This repo ships a GitHub Actions workflow that builds the web app and publishes
it to GitHub Pages, so you can try it in a browser with no local setup.

**One-time setup:** in the repository, open **Settings → Pages** and set
**Build and deployment → Source** to **GitHub Actions**.

After that, every push to this branch (or a manual run from the **Actions** tab →
*Deploy web app to GitHub Pages* → *Run workflow*) builds and deploys the site.
The live URL will be:

```
https://<your-username>.github.io/Phantom-Eye/
```

Open it, paste your Cesium ion token, and explore. (If a deploy is blocked
because it's running from a non-default branch, either allow this branch under
the repo's **github-pages** environment, or merge the branch into `main`.)

## Getting started (local)

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
  (Google Photorealistic 3D Tiles) and ion geocoding
- [OSRM](https://project-osrm.org/) for driving routes and turn-by-turn steps
- [Vite](https://vitejs.dev/) + TypeScript

## Attribution

Google Photorealistic 3D Tiles and Cesium data require on-screen attribution.
Phantom Eye keeps the Cesium credit display visible in the lower-left corner;
please don't remove it.
