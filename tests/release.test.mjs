import { test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

const script = fileURLToPath(new URL("../scripts/release.sh", import.meta.url));
// Formiga Desktop's v0.67.14 release as `gh release view --json assets` shows it: all eight files.
const desktop = readFileSync(new URL("fixtures/desktop-release.json", import.meta.url), "utf8");
const rerun = "Rerun the failed part of its release run, then run this again.";

// Runs one of the script's functions in a bash that has sourced the script, which runs nothing
// itself when sourced. Only the functions that reach neither gh nor git are tried this way.
function run(fn, ...args) {
  const { status, stdout, stderr } = spawnSync("bash", ["-c", 'source "$1"; shift; "$@"', "bash", script, fn, ...args], {
    encoding: "utf8",
  });
  return { status, stdout, stderr };
}

// The release's files renamed, as another app's release would name its own.
function renamed(json, from, to) {
  const { assets } = JSON.parse(json);
  return JSON.stringify({ assets: assets.map((a) => ({ ...a, name: a.name.replace(from, to) })) });
}

test("a version is three numbers with dots, without the v", () => {
  assert.deepEqual(run("check_version", "0.68.0"), { status: 0, stdout: "", stderr: "" });
  for (const bad of ["v0.68.0", "0.68"]) {
    const { status, stderr } = run("check_version", bad);
    assert.equal(status, 1);
    assert.equal(stderr, `"${bad}" is not a version like 0.67.2\n`);
  }
});

test("a release is public, a draft, or not there", () => {
  assert.equal(run("state_of", '{"draft": false}').stdout, "public\n");
  assert.equal(run("state_of", '{"draft": true}').stdout, "draft\n");
  assert.deepEqual(run("state_of", ""), { status: 0, stdout: "", stderr: "" });
});

test("a release's files are counted by app and version", () => {
  assert.equal(run("count_files", desktop, "Formiga", "0.67.14").stdout, "8\n");
  assert.equal(run("count_files", desktop, "Formiga", "0.67.13").stdout, "0\n");
  assert.equal(run("count_files", desktop, "Formiga-Battle", "0.67.14").stdout, "0\n");
  assert.equal(run("count_files", '{"assets": []}', "Formiga", "0.67.14").stdout, "0\n");
});

test("another app's files with the same version are not counted", () => {
  const hill = renamed(desktop, "Formiga-", "Formiga-Hill-");
  const both = JSON.stringify({ assets: [...JSON.parse(desktop).assets, ...JSON.parse(hill).assets] });
  assert.equal(run("count_files", both, "Formiga", "0.67.14").stdout, "8\n");
  assert.equal(run("count_files", both, "Formiga-Hill", "0.67.14").stdout, "8\n");
});

test("a release with all eight files passes", () => {
  assert.deepEqual(run("check_files", "Formiga-Desktop", "v0.67.14", "Formiga", desktop), { status: 0, stdout: "", stderr: "" });
});

test("a release missing a file is refused, with its count", () => {
  const seven = JSON.stringify({ assets: JSON.parse(desktop).assets.slice(1) });
  const { status, stderr } = run("check_files", "Formiga-Desktop", "v0.67.14", "Formiga", seven);
  assert.equal(status, 1);
  assert.equal(stderr, `Formiga-Desktop v0.67.14 has 7 of its 8 files. ${rerun}\n`);
});

test("Battle's release tag names the version its files carry", () => {
  const battle = renamed(desktop, "Formiga-", "Formiga-Battle-");
  assert.equal(run("check_files", "Formiga-World-Releases", "battle-v0.67.14", "Formiga-Battle", battle).status, 0);
  const { status, stderr } = run("check_files", "Formiga-World-Releases", "battle-v0.67.14", "Formiga-Battle", desktop);
  assert.equal(status, 1);
  assert.equal(stderr, `Formiga-World-Releases battle-v0.67.14 has 0 of its 8 files. ${rerun}\n`);
});

test("sourced, the script does nothing; run, it checks its arguments before anything else", () => {
  const sourced = spawnSync("bash", ["-c", 'source "$1"', "bash", script], { encoding: "utf8" });
  assert.deepEqual([sourced.status, sourced.stdout, sourced.stderr], [0, "", ""]);
  const usage = spawnSync("bash", [script], { encoding: "utf8" });
  assert.equal(usage.status, 1);
  assert.equal(usage.stderr, "usage: release.sh build|ship <desktop> [<hill>] [<home>] [<battle>]\n");
  const version = spawnSync("bash", [script, "build", "0.68"], { encoding: "utf8" });
  assert.equal(version.status, 1);
  assert.equal(version.stderr, '"0.68" is not a version like 0.67.2\n');
});
