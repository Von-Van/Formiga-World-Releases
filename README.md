# Formiga World Releases

One place to release Formiga Desktop and its expansions together, in the order they depend on each
other, with two buttons: **Build** and **Ship**. Both are under this repository's Actions tab, as
"Run workflow".

Looking for Formiga itself? Each app's downloads are on its own repository's Releases page,
starting with [Formiga Desktop's](https://github.com/Von-Van/Formiga-Desktop/releases). Formiga
Battle's are on [this repository's](https://github.com/Von-Van/Formiga-World-Releases/releases).

## What a release goes through

1. **Get each app ready, as usual, in its own repository.**
   - Formiga Desktop: merge its release commit, `Release X.Y.Z with …`, with the version moved by
     `scripts/set-version.sh` and its notes written (`docs/BUILD.md`, "Cutting a release").
   - Formiga Hill and Formiga Home: merge the new version's `CHANGELOG.md` section. Build moves
     their version and their Desktop tag itself.
   - Formiga Battle: the same, with its section headed `## [X.Y.Z] - date`.
   - The website, if it should say something new: put the words on a branch of Formiga-Site named
     `release/vX.Y.Z`, after Desktop's version. Ship takes it in last.
2. **Build**, with each app's new version. It tags Desktop, waits for its release to be built,
   then moves each expansion onto Desktop's new tag, commits that to its `main`, tags it and waits
   for it too. Every release comes out as a hidden draft: the website, the in-app updater and
   anyone browsing GitHub see none of it.
3. **Try the drafts.** Each repository's Releases page lists its draft, with all eight downloads.
   Battle's is on this repository's Releases page, as `battle-vX.Y.Z`.
4. **Ship**, with the same versions. It checks every draft has all its files, makes them public
   in the same order, then points the website's downloads at them.

A version left blank leaves that expansion out. A Desktop version that has already been released is
reused, so an expansion can be released on its own. If either button stops partway, fix what it
names and press it again with the same versions: it picks up where it stopped.

## Formiga Battle

Battle's repository runs no Actions, so it is built here: Build moves Battle's version and Desktop
tag and tags it as it does Hill's, then starts `battle.yml`, which checks out that tag, packages it
on macOS and Windows with Battle's own `scripts/package-macos.sh` and `scripts/package-windows.ps1`,
and keeps the downloads as this repository's draft release `battle-vX.Y.Z`. The website offers
Battle from here.

Ship also gives the website's friend-match relay (`lib/battle-builds.mjs` in Formiga-Site) the
SHA-256 of each released Battle program, the app's program on macOS and the `.exe` on Windows, read
from the release's own zips with `scripts/battle-builds.mjs`. From then on only those copies of
that version can play each other.

## How it works

`scripts/release.sh` does both steps; the workflows only run it. Build installs a Rust toolchain
because each expansion's `scripts/set-version.sh` refreshes its `Cargo.lock` for Desktop's new tag.
Each app's own release workflow still does the building: a tag whose message carries the line `Formiga-Release: draft` makes it
publish a draft instead of a public release. `scripts/site-downloads.mjs` changes only the fallback
downloads in the website's `assets/js/config.js`; the page itself always offers the newest public
release.

The buttons act through the `RELEASE_TOKEN` secret, a fine-grained access key limited to Formiga
Desktop, Hill, Home and the website, with read and write access to their contents and read access
to Desktop's, Hill's and Home's Actions (Build only watches their runs; the website has none), and
to Formiga Battle's contents (read and write, so Build can move its version and tag it; Battle
needs no Actions access). Formiga Farm is not released through here yet.
GitHub does not let one repository's workflows start another's without one. What the buttons do
in this repository itself, starting Battle's build and keeping its releases, goes through the
workflows' own token.

`node --test` and `shellcheck scripts/*.sh` are the checks pull requests run. The tests source
`scripts/release.sh` and try its pure checks, the version, the state of a release and the count of
its files, on a saved copy of a real release's file list; nothing that reaches GitHub is run.

## License

MIT. See [LICENSE](LICENSE).
