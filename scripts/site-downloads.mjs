// Points the website's fallback downloads (assets/js/config.js in Formiga-Site) at new releases.
//
//   node scripts/site-downloads.mjs <config.js> desktop=0.67.2 [hill=0.1.2] [home=0.1.2]
//
// Only each component's `fallback` block changes: its tag and the file names in it, which carry
// the version. Everything else in the file, the "needs" lines included, is left for a person.

import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

export function offer(config, versions) {
  let out = config;
  for (const [id, version] of Object.entries(versions)) {
    if (!/^\d+\.\d+\.\d+$/.test(version)) throw new Error(`"${version}" is not a version like 0.67.2`);
    const start = out.indexOf(`id: "${id}"`);
    if (start < 0) throw new Error(`the site has no component "${id}"`);
    const open = out.indexOf("fallback: {", start);
    const next = out.indexOf("id: \"", start + 1);
    if (open < 0 || (next >= 0 && open > next)) throw new Error(`"${id}" has no fallback`);
    const close = out.indexOf("\n      },", open);
    const block = out.slice(open, close);
    const old = block.match(/tag: "v(\d+\.\d+\.\d+)"/);
    if (!old) throw new Error(`"${id}" names no fallback tag`);
    const escaped = old[1].replaceAll(".", "\\.");
    const fresh = block.replace(new RegExp(`(?<![0-9.])${escaped}(?![0-9])`, "g"), version);
    out = out.slice(0, open) + fresh + out.slice(close);
  }
  return out;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const [file, ...pairs] = process.argv.slice(2);
  if (!file || pairs.length === 0) {
    console.error("usage: node scripts/site-downloads.mjs <config.js> desktop=0.67.2 [hill=0.1.2] [home=0.1.2]");
    process.exit(2);
  }
  const versions = Object.fromEntries(pairs.map((pair) => pair.split("=")));
  writeFileSync(file, offer(readFileSync(file, "utf8"), versions));
}
