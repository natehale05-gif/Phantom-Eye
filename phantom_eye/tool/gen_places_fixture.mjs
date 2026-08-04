/**
 * Regenerates packages/pe_domain/test/fixtures/places_reference.json.
 *
 * Like gen_category_fixture.mjs and gen_routing_fixture.mjs, this compiles and
 * imports the REAL src/places.ts via esbuild, so the curated camera framings
 * are read straight from the shipping source. Those framings are hand-tuned
 * and not derivable from the coordinate — a transcription slip in the heading
 * or pitch would silently ruin the arrival shot for one destination, which no
 * hand-written expectation would catch.
 *
 * Usage, from the repository root:
 *   node phantom_eye/tool/gen_places_fixture.mjs
 *
 * Requires `npm ci` (esbuild is already a devDependency).
 */

import { build } from 'esbuild';
import { mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';

const repoRoot = resolve(import.meta.dirname, '../..');

const entry = `
import { PLACES } from ${JSON.stringify(join(repoRoot, 'src/places.ts'))};

const out = {
  places: PLACES.map((p) => ({
    id: p.id,
    name: p.name,
    region: p.region,
    lon: p.lon,
    lat: p.lat,
    cameraHeightMeters: p.height,
    headingDegrees: p.heading,
    pitchDegrees: p.pitch,
  })),
};
process.stdout.write(JSON.stringify(out));
`;

const dir = await mkdtemp(join(tmpdir(), 'pe-placesfix-'));
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
