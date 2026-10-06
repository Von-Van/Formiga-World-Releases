#!/usr/bin/env bash
# Builds and ships Formiga Desktop and its expansions together, in the order they depend on each
# other: Desktop first, then each expansion on Desktop's new tag, then the website.
#
#   scripts/release.sh build <desktop> [<hill>] [<home>]
#     Tags each app as a hidden draft release and waits for every draft to have all its files.
#     Desktop's main must already be its release commit (scripts/set-version.sh and its notes, as
#     docs/BUILD.md describes); a Desktop version that is already tagged is reused, so the
#     expansions can be released on their own. Each expansion's CHANGELOG.md must already have the
#     new version's section; this moves its version and Desktop tag, commits that to its main, and
#     tags it.
#
#   scripts/release.sh ship <desktop> [<hill>] [<home>]
#     Makes those drafts public in the same order, then points the website's downloads at them,
#     taking in the website's release/v<desktop> branch first when there is one.
#
# Versions are written without the v, e.g. 0.67.2. A blank version skips that expansion. Running
# either command again picks up where an interrupted run stopped. Needs gh, jq, git and cargo, and
# GH_TOKEN with read and write access to the repositories below.

set -euo pipefail

owner=Von-Van
desktop=Formiga-Desktop
site=Formiga-Site
# Each expansion: repository, then the name its downloads start with. Their order is the order they
# are built and shipped in.
expansions=(
  "Formiga-Hill Formiga-Hill"
  "Formiga-Home Formiga-Home"
)
# Every release carries a DMG, an MSI and two portable ZIPs, each with its .sha256.
files_per_release=8

here="$(cd "$(dirname "$0")" && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

say() { printf '%s\n' "$*"; }
fail() {
  printf '%s\n' "$*" >&2
  exit 1
}

check_version() {
  [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "\"$1\" is not a version like 0.67.2"
}

# Commits are made as the person whose key this is, so they read as theirs on GitHub.
git_identity() {
  local login id
  login="$(gh api user --jq .login)"
  id="$(gh api user --jq .id)"
  git -C "$1" config user.name "$login"
  git -C "$1" config user.email "$id+$login@users.noreply.github.com"
}

clone() {
  git clone --quiet "https://x-access-token:$GH_TOKEN@github.com/$owner/$1.git" "$work/$1"
  git_identity "$work/$1"
}

tag_exists() {
  [ -n "$(git ls-remote --tags "https://x-access-token:$GH_TOKEN@github.com/$owner/$1.git" "refs/tags/$2")" ]
}

# The release for a tag, drafts included, which GitHub's lookup by tag leaves out.
release_json() {
  gh api "repos/$owner/$1/releases?per_page=30" --jq "[.[] | select(.tag_name == \"$2\")][0] // empty"
}

# Prints "draft" or "public" for a release, or nothing when there is none.
release_state() {
  release_json "$1" "$2" | jq -r 'if .draft then "draft" else "public" end'
}

# A release is whole when it has every file, each named for this app and version.
check_files() {
  local repo="$1" tag="$2" prefix="$3" count
  count="$(release_json "$repo" "$tag" | jq -r '.assets[].name' | grep -c "^$prefix-${tag#v}-" || true)"
  [ "$count" -eq "$files_per_release" ] ||
    fail "$repo $tag has $count of its $files_per_release files. Rerun the failed part of its release run, then run this again."
}

# Waits for the release run a tag started, then checks the draft it made.
wait_for_release() {
  local repo="$1" tag="$2" prefix="$3" run="" tries=0
  say "Waiting for $repo's release run for $tag."
  while [ -z "$run" ]; do
    run="$(gh run list -R "$owner/$repo" --workflow release.yml --event push --limit 20 \
      --json databaseId,headBranch --jq "[.[] | select(.headBranch == \"$tag\")][0].databaseId // empty")"
    if [ -z "$run" ]; then
      tries=$((tries + 1))
      [ "$tries" -le 30 ] || fail "$repo's release run for $tag never started."
      sleep 10
    fi
  done
  gh run watch "$run" -R "$owner/$repo" --exit-status --interval 30 >/dev/null ||
    fail "$repo's release run for $tag failed: https://github.com/$owner/$repo/actions/runs/$run. Rerun its failed jobs once the cause is fixed, then run this again."
  [ "$(release_state "$repo" "$tag")" = draft ] || fail "$repo $tag was not published as a draft."
  check_files "$repo" "$tag" "$prefix"
  say "$repo $tag is a draft with all its files."
}

tag_release() {
  local repo="$1" tag="$2" message="$3"
  git -C "$work/$repo" tag -a "$tag" -m "$message" -m "Formiga-Release: draft"
  git -C "$work/$repo" push --quiet origin "refs/tags/$tag"
}

build_desktop() {
  local version="$1" tag="v$1" dir="$work/$desktop" subject state
  state="$(release_state "$desktop" "$tag")"
  if [ -n "$state" ]; then
    check_files "$desktop" "$tag" Formiga
    say "$desktop $tag is already a $state release; using it."
    return
  fi
  if ! tag_exists "$desktop" "$tag"; then
    clone "$desktop"
    [ "$(sed -n 's/^version = "\(.*\)"$/\1/p' "$dir/Cargo.toml" | head -n 1)" = "$version" ] ||
      fail "$desktop's main is not at $version yet. Merge its release commit first (docs/BUILD.md, Cutting a release)."
    (cd "$dir" && scripts/set-version.sh --check)
    grep -qx "## New in $version" "$dir/docs/RELEASE_NOTES.md" ||
      fail "$desktop's docs/RELEASE_NOTES.md has no \"## New in $version\" section."
    subject="$(git -C "$dir" log -1 --format=%s)"
    [[ "$subject" == "Release $version"* ]] ||
      fail "$desktop's main ends with \"$subject\", not its release commit for $version."
    tag_release "$desktop" "$tag" "$subject"
  fi
  wait_for_release "$desktop" "$tag" Formiga
}

build_expansion() {
  local repo="$1" prefix="$2" version="$3" desktop_tag="$4" tag="v$3" dir="$work/$1" subject state
  state="$(release_state "$repo" "$tag")"
  if [ -n "$state" ]; then
    check_files "$repo" "$tag" "$prefix"
    say "$repo $tag is already a $state release; using it."
    return
  fi
  if ! tag_exists "$repo" "$tag"; then
    clone "$repo"
    grep -q "^## $version " "$dir/CHANGELOG.md" ||
      fail "$repo's CHANGELOG.md has no section for $version yet. Merge it first."
    (cd "$dir" && scripts/set-version.sh "$version" "$desktop_tag" && scripts/set-version.sh --check)
    subject="Take Desktop's $desktop_tag and release $version"
    if ! git -C "$dir" diff --quiet; then
      git -C "$dir" commit --quiet -am "$subject"
      git -C "$dir" push --quiet origin HEAD:main
    fi
    tag_release "$repo" "$tag" "$subject"
  fi
  wait_for_release "$repo" "$tag" "$prefix"
}

# Points the website's fallback downloads at the new releases. The page itself always asks GitHub
# for the newest public release; the fallback is what it offers when GitHub cannot be reached.
ship_site() {
  local desktop_version="$1" hill="$2" home="$3" dir="$work/$site" branch="release/v$1" names
  clone "$site"
  if git -C "$dir" ls-remote --exit-code --heads origin "$branch" >/dev/null; then
    git -C "$dir" fetch --quiet origin "$branch"
    git -C "$dir" merge --quiet --squash "origin/$branch" ||
      fail "$site's $branch no longer merges cleanly into main. Bring main into it, then run this again."
  fi
  node "$here/site-downloads.mjs" "$dir/assets/js/config.js" \
    "desktop=$desktop_version" ${hill:+"hill=$hill"} ${home:+"home=$home"}
  git -C "$dir" add -A
  if git -C "$dir" diff --cached --quiet; then
    say "$site already offers these releases."
    return
  fi
  names="Desktop $desktop_version${hill:+, Hill $hill}${home:+, Home $home}"
  git -C "$dir" commit --quiet -m "Offer $names"
  git -C "$dir" push --quiet origin HEAD:main
  say "$site now offers $names."
}

command="${1:-}"
desktop_version="${2:-}"
[[ "$command" =~ ^(build|ship)$ ]] && [ -n "$desktop_version" ] ||
  fail "usage: $(basename "$0") build|ship <desktop> [<hill>] [<home>]"
versions=("${3:-}" "${4:-}")
check_version "$desktop_version"
for v in "${versions[@]}"; do [ -z "$v" ] || check_version "$v"; done
: "${GH_TOKEN:?GH_TOKEN must be set}"

if [ "$command" = build ]; then
  build_desktop "$desktop_version"
  for i in "${!expansions[@]}"; do
    [ -n "${versions[$i]}" ] || continue
    read -r repo prefix <<<"${expansions[$i]}"
    build_expansion "$repo" "$prefix" "${versions[$i]}" "v$desktop_version"
  done
  say "Every draft is ready to try. Run ship with the same versions to make them public."
  exit 0
fi

# Ship: check every draft is whole before making any of them public, so a half-built set never
# goes out.
releases=("$desktop Formiga v$desktop_version")
for i in "${!expansions[@]}"; do
  [ -n "${versions[$i]}" ] || continue
  read -r repo prefix <<<"${expansions[$i]}"
  releases+=("$repo $prefix v${versions[$i]}")
done
for entry in "${releases[@]}"; do
  read -r repo prefix tag <<<"$entry"
  [ -n "$(release_state "$repo" "$tag")" ] || fail "$repo has no $tag release. Run build first."
  check_files "$repo" "$tag" "$prefix"
done
for entry in "${releases[@]}"; do
  read -r repo prefix tag <<<"$entry"
  if [ "$(release_state "$repo" "$tag")" = draft ]; then
    gh release edit "$tag" -R "$owner/$repo" --draft=false --latest >/dev/null
    say "$repo $tag is public."
  else
    say "$repo $tag was already public."
  fi
done
ship_site "$desktop_version" "${versions[0]}" "${versions[1]}"
