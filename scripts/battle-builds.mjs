// Gives the website's friend-match relay (lib/battle-builds.mjs in Formiga-Site) the digests of a
// Formiga Battle release: the SHA-256 of each released program, one per platform. Once a version
// is listed, only those copies of it can open or join a room.
//
//   node scripts/battle-builds.mjs <battle-builds.mjs> 0.67.8 <mac digest> <windows digest>
//
// The list is written as JSON inside the file's `Object.freeze(…)`, so it reads back the same way.
// A released version's builds never change: listing it again with other digests is refused.

import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

const LIST = /(export const RELEASED_BUILDS = Object\.freeze\()([\s\S]*)(\);\s*)$/;

export function list(file, version, digests) {
  if (!/^\d+\.\d+\.\d+$/.test(version)) throw new Error(`"${version}" is not a version like 0.67.8`);
  if (digests.length === 0) throw new Error(`Battle ${version} has no digests to list`);
  for (const d of digests) {
    if (!/^[0-9a-f]{64}$/.test(d)) throw new Error(`"${d}" is not a SHA-256 as 64 lowercase hex digits`);
  }
  const found = file.match(LIST);
  if (!found) throw new Error("the file has no RELEASED_BUILDS = Object.freeze(…) at its end");
  const builds = JSON.parse(found[2]);
  const wanted = [...new Set(digests)];
  if (Object.hasOwn(builds, version)) {
    const known = builds[version];
    const same = known.length === wanted.length && wanted.every((d) => known.includes(d));
    if (same) return file;
    throw new Error(`Battle ${version} is already listed with other digests; a released version's builds never change`);
  }
  builds[version] = wanted;
  return file.replace(LIST, (_, open, _body, close) => `${open}${JSON.stringify(builds, null, 2)}${close}`);
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const [file, version, ...digests] = process.argv.slice(2);
  if (!file || !version) {
    console.error("usage: node scripts/battle-builds.mjs <battle-builds.mjs> <version> <digest>...");
    process.exit(2);
  }
  writeFileSync(file, list(readFileSync(file, "utf8"), version, digests));
}
