/**
 * Regenerates packages/pe_data/test/fixtures/routing_reference.json.
 *
 * Like gen_category_fixture.mjs, this compiles and imports the REAL
 * src/routing.ts via esbuild rather than embedding a copy — so maneuver
 * classification and instruction wording are read from the shipping source
 * and cannot drift from the Dart port without breaking the build.
 *
 * `classify` and `describe` are module-private in routing.ts, so they are
 * reached the way the app reaches them: through the exported `fetchRoutes`,
 * with `fetch` stubbed to return a synthetic OSRM response. That has the
 * useful side effect of covering `parseRoute`'s leg flattening and its
 * distance/duration defaulting at the same time.
 *
 * Usage, from the repository root:
 *   node phantom_eye/tool/gen_routing_fixture.mjs
 *
 * Requires `npm ci` (esbuild is already a devDependency).
 */

import { build } from 'esbuild';
import { mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';

const repoRoot = resolve(import.meta.dirname, '../..');

/**
 * Every OSRM maneuver type the app can meet, including the ones that carry no
 * distinguishing type and are described entirely by their modifier.
 */
const TYPES = [
  'depart',
  'arrive',
  'roundabout',
  'rotary',
  'merge',
  'on ramp',
  'off ramp',
  'turn',
  'continue',
  'new name',
  'fork',
  'end of road',
  'exit roundabout',
  'notify',
  undefined,
];

/**
 * Modifiers, including `sharp uturn` — which must classify as a u-turn via
 * the substring test, not fall through to `sharp left`/`sharp right`.
 */
const MODIFIERS = [
  'left',
  'right',
  'slight left',
  'slight right',
  'sharp left',
  'sharp right',
  'uturn',
  'sharp uturn',
  'straight',
  'unknown modifier',
  undefined,
];

/** Road names, covering present, absent, and whitespace-only. */
const NAMES = ['Main St', '', '   ', undefined];

const entry = `
import { fetchRoutes } from ${JSON.stringify(join(repoRoot, 'src/routing.ts'))};

const types = ${JSON.stringify(TYPES)};
const modifiers = ${JSON.stringify(MODIFIERS)};
const names = ${JSON.stringify(NAMES)};

const cases = [];
for (const type of types)
  for (const modifier of modifiers)
    for (const name of names)
      cases.push({ type, modifier, name });

// One step per case, split across two legs so leg flattening is exercised.
const half = Math.ceil(cases.length / 2);
const toStep = (c) => ({
  name: c.name,
  distance: 12.5,
  maneuver: {
    type: c.type,
    modifier: c.modifier,
    location: [-122.0, 37.0],
  },
});

const body = {
  code: 'Ok',
  routes: [
    {
      geometry: { coordinates: [[-122.0, 37.0], [-122.001, 37.001]] },
      legs: [
        { steps: cases.slice(0, half).map(toStep) },
        { steps: cases.slice(half).map(toStep) },
      ],
      distance: 1234.5,
      duration: 678.9,
    },
    // A second route with no legs and no distance/duration, to pin the
    // alternates path and the zero defaults.
    { geometry: { coordinates: [[-122.0, 37.0], [-122.002, 37.002]] } },
  ],
};

globalThis.fetch = async () => ({ ok: true, status: 200, json: async () => body });

// An async IIFE rather than top-level await: the bundle is emitted as CJS so
// it can be run directly by node without a package.json type marker.
(async () => {
  const routes = await fetchRoutes([-122.0, 37.0], [-122.002, 37.002]);
  const primary = routes[0];

  const out = {
    maneuvers: cases.map((c, i) => ({
      type: c.type ?? null,
      modifier: c.modifier ?? null,
      name: c.name ?? null,
      kind: primary.steps[i].kind,
      instruction: primary.steps[i].instruction,
    })),
    routeCount: routes.length,
    stepCount: primary.steps.length,
    distance: primary.distance,
    duration: primary.duration,
    alternateDistance: routes[1].distance,
    alternateDuration: routes[1].duration,
    alternateStepCount: routes[1].steps.length,
  };
  process.stdout.write(JSON.stringify(out));
})();
`;

const dir = await mkdtemp(join(tmpdir(), 'pe-routefix-'));
try {
  const entryPath = join(dir, 'entry.ts');
  await writeFile(entryPath, entry, 'utf8');
  const bundlePath = join(dir, 'bundle.cjs');
  await build({
    entryPoints: [entryPath],
    bundle: true,
    platform: 'node',
    format: 'cjs',
    outfile: bundlePath,
    logLevel: 'error',
  });
  const { execFileSync } = await import('node:child_process');
  process.stdout.write(execFileSync(process.execPath, [bundlePath], { encoding: 'utf8' }));
} finally {
  await rm(dir, { recursive: true, force: true });
}
