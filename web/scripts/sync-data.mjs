// Copy the study's committed JSON into the site so the frontend has a single source of truth
// with the contract and the analysis. Runs before dev and before build.
// Nothing here transforms a number: it is a copy, on purpose.
import { copyFileSync, mkdirSync, existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const from = join(here, "..", "..", "data");
const to = join(here, "..", "data");
const files = ["economics.json", "stats.json", "gas_overhead.json", "gas_economics.json"];

mkdirSync(to, { recursive: true });
for (const f of files) {
  const src = join(from, f);
  if (!existsSync(src)) {
    console.error(`sync-data: missing ${src} — run analysis/run.sh first`);
    process.exit(1);
  }
  copyFileSync(src, join(to, f));
}
console.log(`sync-data: copied ${files.length} files from data/`);
