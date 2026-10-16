import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync, writeFileSync, mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { list } from "../scripts/battle-builds.mjs";

// A copy of Formiga-Site's lib/battle-builds.mjs as it stands before any Battle release is listed.
const file = readFileSync(new URL("fixtures/battle-builds.mjs", import.meta.url), "utf8");
const mac = "a".repeat(64);
const windows = "b".repeat(64);

// What the relay would read from the file: it is imported as the module it is.
async function released(text) {
  const path = join(mkdtempSync(join(tmpdir(), "battle-builds-")), "battle-builds.mjs");
  writeFileSync(path, text);
  return (await import(path)).RELEASED_BUILDS;
}

test("a release's digests are what the relay then knows", async () => {
  const out = list(file, "0.67.8", [mac, windows]);
  assert.deepEqual(await released(out), { "0.67.8": [mac, windows] });
  assert.ok(Object.isFrozen(await released(out)));
});

test("the comment above the list is kept", () => {
  const out = list(file, "0.67.8", [mac, windows]);
  const comment = (text) => text.slice(0, text.indexOf("export const"));
  assert.equal(comment(out), comment(file));
});

test("a second release is listed beside the first", async () => {
  const out = list(list(file, "0.67.8", [mac, windows]), "0.67.9", ["c".repeat(64)]);
  assert.deepEqual(Object.keys(await released(out)), ["0.67.8", "0.67.9"]);
});

test("listing the same digests again changes nothing", () => {
  const once = list(file, "0.67.8", [mac, windows]);
  assert.equal(list(once, "0.67.8", [windows, mac]), once);
});

test("a released version is never given other digests", () => {
  const once = list(file, "0.67.8", [mac, windows]);
  assert.throws(() => list(once, "0.67.8", [mac, "c".repeat(64)]), /never change/);
});

test("a malformed version or digest is refused", () => {
  assert.throws(() => list(file, "v0.67.8", [mac]), /not a version/);
  assert.throws(() => list(file, "0.67.8", ["A".repeat(64)]), /not a SHA-256/);
  assert.throws(() => list(file, "0.67.8", []), /no digests/);
});
