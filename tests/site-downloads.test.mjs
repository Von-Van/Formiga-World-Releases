import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { offer } from "../scripts/site-downloads.mjs";

// A copy of Formiga-Site's assets/js/config.js as it stood with Desktop 0.67.1, Hill 0.1.1 and
// Home 0.1.1.
const config = readFileSync(new URL("fixtures/site-config.js", import.meta.url), "utf8");

test("each fallback names the new tag and files", () => {
  const out = offer(config, { desktop: "0.67.2", hill: "0.1.2", home: "0.1.2" });
  assert.match(out, /tag: "v0\.67\.2",\n {8}files: \{\n {10}mac: "Formiga-0\.67\.2-macOS-universal\.dmg",\n {10}windows: "Formiga-0\.67\.2-windows-x64\.msi"/);
  assert.match(out, /mac: "Formiga-Hill-0\.1\.2-macOS-universal\.dmg"/);
  assert.match(out, /windows: "Formiga-Home-0\.1\.2-windows-x64\.msi"/);
  assert.doesNotMatch(out, /0\.67\.1|0\.1\.1/);
});

test("only the fallbacks change", () => {
  const out = offer(config, { desktop: "0.67.2", hill: "0.1.2", home: "0.1.2" });
  const outside = (text) => text.replace(/fallback: \{[\s\S]*?\n {6}\},/g, "");
  assert.equal(outside(out), outside(config));
  assert.match(out, /needs: "Formiga Desktop 0\.66\.4 or later"/);
});

test("an expansion left out keeps its release", () => {
  const out = offer(config, { desktop: "0.67.2" });
  assert.match(out, /Formiga-Hill-0\.1\.1-macOS/);
  assert.match(out, /Formiga-Home-0\.1\.1-windows/);
});

test("offering the same versions again changes nothing", () => {
  const once = offer(config, { desktop: "0.67.2", hill: "0.1.2" });
  assert.equal(offer(once, { desktop: "0.67.2", hill: "0.1.2" }), once);
});

test("an unknown component or a malformed version is refused", () => {
  assert.throws(() => offer(config, { farm: "0.1.0" }), /no component "farm"/);
  assert.throws(() => offer(config, { desktop: "v0.67.2" }), /not a version/);
});
