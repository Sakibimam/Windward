// Copy the study's committed JSON into the site so the frontend has a single source of truth
// with the contract and the analysis. Runs before dev and before build.
// Nothing here transforms a number: it is a copy, on purpose.
import { copyFileSync, mkdirSync, existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const from = join(here, "..", "..", "data");
const to = join(here, "..", "data");
const files = ["economics.json", "stats.json", "staleness.json", "gas_overhead.json", "gas_economics.json"];

mkdirSync(to, { recursive: true });
let copied = 0;
for (const f of files) {
  const src = join(from, f);
  const dest = join(to, f);
  if (existsSync(src)) {
    copyFileSync(src, dest);
    copied++;
  } else if (!existsSync(dest)) {
    console.error(`sync-data: missing ${src} and no pre-existing ${dest} found — run analysis/run.sh first`);
    process.exit(1);
  }
}
if (copied > 0) {
  console.log(`sync-data: copied ${copied} files from data/`);
} else {
  console.log(`sync-data: using pre-existing data files in web/data/`);
}
