/**
 * Regenerates packages/pe_domain/test/fixtures/category_reference.json.
 *
 * Unlike gen_legacy_fixture.mjs (which embeds copies of small pure functions),
 * this compiles and imports the REAL src/categories.ts via esbuild. That means
 * the category table and matchCategory behaviour are read straight from the
 * shipping source, so there is no second copy to drift — if someone edits a
 * keyword list in TypeScript, the Dart port's parity test fails until it is
 * regenerated.
 *
 * Usage, from the repository root:
 *   node phantom_eye/tool/gen_category_fixture.mjs
 *
 * Requires `npm ci` (esbuild is already a devDependency).
 */

import { build } from 'esbuild';
import { mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';

const repoRoot = resolve(import.meta.dirname, '../..');

/**
 * Queries chosen to exercise every branch of matchCategory: exact labels,
 * case handling, multi-word keywords, filler stripping, the three-token cap,
 * digit stripping, accented input, and inputs that must NOT match.
 */
const PROBES = [
  // exact labels and casing
  'food', 'Food', 'FOOD',
  // plain keywords
  'dinner', 'coffee', 'gas', 'pizza', 'sushi', 'burgers',
  'park', 'parks', 'playground', 'surf', 'waves', 'beach', 'camp', 'camping',
  // accented input must survive the letter filter
  'café',
  // multi-word keywords: only reachable via the whole-phrase pass
  'gas station', 'food store', 'ski resort', 'rock climbing', 'driving range',
  // filler stripping
  'best coffee near me', 'good food nearby', 'the closest gas',
  'some places to eat', 'cheap hotels around me', 'open bars', 'a bar',
  'nearest atm',
  // digits are stripped
  '76 gas', '7-eleven', 'shell 12', '123',
  // specific place names must fall through to geocoding
  'starbucks', 'joes diner', 'wilderness',
  // over the three-token cap
  'coffee shop downtown seattle',
  'this is a very long query with many words indeed',
  // degenerate
  '', '   ', '!!!',
];

const entry = `
import { CATEGORIES, DEFAULT_PIN_COLOR, matchCategory } from ${JSON.stringify(
  join(repoRoot, 'src/categories.ts'),
)};

const probes = ${JSON.stringify(PROBES)};

const out = {
  defaultPinColorHex: DEFAULT_PIN_COLOR,
  categories: CATEGORIES.map((c) => ({
    id: c.id,
    label: c.label,
    colorHex: c.color,
    osmTags: c.osm.map(([k, v]) => k + '=' + v),
    keywords: c.keywords,
  })),
  matches: probes.map((q) => ({ q, id: matchCategory(q)?.id ?? null })),
};
process.stdout.write(JSON.stringify(out));
`;

const dir = await mkdtemp(join(tmpdir(), 'pe-catfix-'));
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
