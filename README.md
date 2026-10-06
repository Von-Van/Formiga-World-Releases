# Formiga World Releases

One place to release Formiga Desktop and its expansions together, in the order they depend on each
other, with two buttons: **Build** and **Ship**. Both are under this repository's Actions tab, as
"Run workflow".

## What a release goes through

1. **Get each app ready, as usual, in its own repository.**
   - Formiga Desktop: merge its release commit, `Release X.Y.Z with …`, with the version moved by
     `scripts/set-version.sh` and its notes written (`docs/BUILD.md`, "Cutting a release").
   - Formiga Hill and Formiga Home: merge the new version's `CHANGELOG.md` section. Build moves
     their version and their Desktop tag itself.
   - The website, if it should say something new: put the words on a branch of Formiga-Site named
     `release/vX.Y.Z`, after Desktop's version. Ship takes it in last.
2. **Build**, with each app's new version. It tags Desktop, waits for its release to be built,
   then moves each expansion onto Desktop's new tag, commits that to its `main`, tags it and waits
   for it too. Every release comes out as a hidden draft: the website, the in-app updater and
   anyone browsing GitHub see none of it.
3. **Try the drafts.** Each repository's Releases page lists its draft, with all eight downloads.
4. **Ship**, with the same versions. It checks every draft has all its files, makes them public
   in the same order, then points the website's downloads at them.

A version left blank leaves that expansion out. A Desktop version that has already been released is
reused, so an expansion can be released on its own. If either button stops partway, fix what it
names and press it again with the same versions: it picks up where it stopped.

## How it works

`scripts/release.sh` does both steps; the workflows only run it. Each app's own release workflow
still does the building: a tag whose message carries the line `Formiga-Release: draft` makes it
publish a draft instead of a public release. `scripts/site-downloads.mjs` changes only the fallback
downloads in the website's `assets/js/config.js`; the page itself always offers the newest public
release.

The buttons act through the `RELEASE_TOKEN` secret, a fine-grained access key limited to Formiga
Desktop, Hill, Home, Farm and the website, with read and write access to their contents and
Actions. GitHub does not let one repository's workflows start another's without one.

`node --test` and `shellcheck scripts/*.sh` are the checks pull requests run.
