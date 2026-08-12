// Pull ABIs straight out of the Foundry build output.
//
// Nothing here is hand-copied: `forge build` writes out/<Contract>.sol/<Contract>.json, and this
// reads those and emits a single typed module. Re-run (it happens automatically on `npm run dev`)
// after any contract change and the UI picks up the new ABI with no manual step.

import {readFileSync, writeFileSync, mkdirSync, existsSync} from 'node:fs';
import {dirname, join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const root = resolve(here, '..', '..');
const outDir = join(root, 'out');
const dest = join(here, '..', 'lib', 'generated');

const CONTRACTS = [
  'RUN',
  'AUG',
  'StockRunner',
  'ERC6551Account',
  'Augments',
  'ExpansionModules',
  'Ripperdoc',
  'BlackMarket',
  'RevenueSplitter',
  'TestnetRunPriceOracle',
  'Terminal',
  'MockLpToken',
  'Fixer',
  'ProtocolReserve',
  'ChopShop',
  'MockUSDG',
  'CommitRevealRandomness',
  'Drop',
  'MockRwaVenue',
];

if (!existsSync(outDir)) {
  console.error(`\n  Foundry build output not found at ${outDir}`);
  console.error('  Run `forge build` in the repo root first.\n');
  process.exit(1);
}

let ts = `// GENERATED FILE — do not edit.\n// Produced by ui/scripts/extract-abis.mjs from Foundry's out/ directory.\n// Regenerate with: npm run abis\n\n`;

for (const name of CONTRACTS) {
  const path = join(outDir, `${name}.sol`, `${name}.json`);
  if (!existsSync(path)) {
    console.error(`  missing artifact: ${path}`);
    process.exit(1);
  }
  const artifact = JSON.parse(readFileSync(path, 'utf8'));
  ts += `export const ${name}Abi = ${JSON.stringify(artifact.abi)} as const;\n\n`;
}

mkdirSync(dest, {recursive: true});
writeFileSync(join(dest, 'abis.ts'), ts);
console.log(`  wrote ${CONTRACTS.length} ABIs -> lib/generated/abis.ts`);
