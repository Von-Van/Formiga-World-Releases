#!/usr/bin/env bash
# Builds and ships Formiga Desktop and its expansions together, in the order they depend on each
# other: Desktop first, then each expansion on Desktop's new tag, then the website.
#
#   scripts/release.sh build <desktop> [<hill>] [<home>] [<battle>]
#     Tags each app as a hidden draft release and waits for every draft to have all its files.
#     Desktop's main must already be its release commit (scripts/set-version.sh and its notes, as
#     docs/BUILD.md describes); a Desktop version that is already tagged is reused, so the
#     expansions can be released on their own. Each expansion's CHANGELOG.md must already have the
#     new version's section; this moves its version and Desktop tag, commits that to its main, and
#     tags it. Formiga Battle goes through the same steps, but its repository runs no Actions, so
#     this repository's battle.yml builds it from its tag and keeps its downloads here, as the
#     release battle-v<battle>.
#
#   scripts/release.sh ship <desktop> [<hill>] [<home>] [<battle>]
#     Makes those drafts public in the same order, then points the website's downloads at them,
#     taking in the website's release/v<desktop> branch first when there is one. For Battle it also
#     gives the website's friend-match relay the digests of the released programs, so only those
#     copies of that version can play each other.
#
# Versions are written without the v, e.g. 0.67.2. A blank version skips that expansion. Running
# either command again picks up where an interrupted run stopped. Needs gh, jq, git, cargo, node and
# unzip, GH_TOKEN with read and write access to the repositories below, and RELEASES_TOKEN for this
# repository itself (its workflows' own token), which starts Battle's build and keeps its releases.

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
# Formiga Battle's repository, and this one, which builds it and keeps its downloads.
battle=Formiga-Battle
releases_repo=Formiga-World-Releases
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
  read -r login id < <(gh api user --jq '"\(.login) \(.id)"')
  git -C "$1" config user.name "$login"
  git -C "$1" config user.email "$id+$login@users.noreply.github.com"
}

remote() {
  printf 'https://x-access-token:%s@github.com/%s/%s.git' "$GH_TOKEN" "$owner" "$1"
}

clone() {
  git clone --quiet "$(remote "$1")" "$work/$1"
  git_identity "$work/$1"
}

# gh for a repository: this one through its own token, any other through GH_TOKEN.
gh_on() {
  local repo="$1"
  shift
  if [ "$repo" = "$releases_repo" ]; then
    GH_TOKEN="${RELEASES_TOKEN:-$GH_TOKEN}" gh "$@"
  else
    gh "$@"
  fi
}

tag_exists() {
  [ -n "$(git ls-remote --tags "$(remote "$1")" "refs/tags/$2")" ]
}

# The release for a tag, drafts included, which GitHub's lookup by tag leaves out.
release_json() {
  gh_on "$1" api --paginate "repos/$owner/$1/releases?per_page=100" --jq ".[] | select(.tag_name == \"$2\")" |
    jq -sc '.[0] // empty'
}

# Prints "draft" or "public" for a release's JSON, or nothing when there is none.
state_of() {
  jq -r 'if .draft then "draft" else "public" end' <<<"$1"
}

# A release, given its JSON, is whole when it has every file, each named for this app and version.
check_files() {
  local repo="$1" tag="$2" prefix="$3" json="$4" count
  count="$(jq -r '.assets[].name' <<<"$json" | grep -c "^$prefix-${tag##*v}-" || true)"
  [ "$count" -eq "$files_per_release" ] ||
    fail "$repo $tag has $count of its $files_per_release files. Rerun the failed part of its release run, then run this again."
}

# Waits for the release run a tag started, then checks the draft it made.
wait_for_release() {
  local repo="$1" tag="$2" prefix="$3" run="" tries=0 json
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
  json="$(release_json "$repo" "$tag")"
  [ "$(state_of "$json")" = draft ] || fail "$repo $tag was not published as a draft."
  check_files "$repo" "$tag" "$prefix" "$json"
  say "$repo $tag is a draft with all its files."
}

tag_release() {
  local repo="$1" tag="$2" message="$3"
  git -C "$work/$repo" tag -a "$tag" -m "$message" -m "Formiga-Release: draft"
  git -C "$work/$repo" push --quiet origin "refs/tags/$tag"
}

build_desktop() {
  local version="$1" tag="v$1" dir="$work/$desktop" subject json state
  json="$(release_json "$desktop" "$tag")"
  state="$(state_of "$json")"
  if [ -n "$state" ]; then
    check_files "$desktop" "$tag" Formiga "$json"
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
  local repo="$1" prefix="$2" version="$3" desktop_tag="$4" tag="v$3" dir="$work/$1" subject json state
  json="$(release_json "$repo" "$tag")"
  state="$(state_of "$json")"
  if [ -n "$state" ]; then
    check_files "$repo" "$tag" "$prefix" "$json"
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

# Battle's build for a version: the run already going for it, or a new one, waited for.
battle_runs() {
  gh_on "$releases_repo" run list -R "$owner/$releases_repo" --workflow battle.yml --limit 20 \
    --json databaseId,displayTitle,status \
    --jq ".[] | select(.displayTitle == \"Battle $1\" and ($2)) | .databaseId"
}

run_battle_build() {
  local version="$1" run before tries=0
  run="$(battle_runs "$version" '.status != "completed"' | head -n 1)"
  if [ -z "$run" ]; then
    before="$(battle_runs "$version" true)"
    gh_on "$releases_repo" workflow run battle.yml -R "$owner/$releases_repo" -f "version=$version"
    while [ -z "$run" ]; do
      tries=$((tries + 1))
      [ "$tries" -le 30 ] || fail "Battle's build for $version never started."
      sleep 10
      run="$(battle_runs "$version" true | grep -vxF -e "${before:-none}" | head -n 1 || true)"
    done
  fi
  say "Waiting for Battle's build for $version."
  gh_on "$releases_repo" run watch "$run" -R "$owner/$releases_repo" --exit-status --interval 30 >/dev/null ||
    fail "Battle's build for $version failed: https://github.com/$owner/$releases_repo/actions/runs/$run. Rerun its failed jobs once the cause is fixed, then run this again."
}

# The SHA-256 of each released Battle program, Mac's then Windows', read from the release's own
# zips: the program inside the app, and the .exe the installer carries too. These are the files
# Battle digests itself when it enters a friend match.
battle_digests() {
  local version="$1" dir="$work/battle-$1"
  rm -rf "$dir"
  mkdir -p "$dir"
  gh_on "$releases_repo" release download "battle-v$version" -R "$owner/$releases_repo" -D "$dir" -p "*.zip"
  unzip -q "$dir/Formiga-Battle-$version-macOS-universal.zip" -d "$dir/mac"
  unzip -q "$dir/Formiga-Battle-$version-windows-x64.zip" -d "$dir/windows"
  for program in "$dir/mac/Formiga Battle.app/Contents/MacOS/Formiga Battle" "$dir/windows/Formiga Battle.exe"; do
    [ -f "$program" ] || fail "Battle $version's downloads have no ${program#"$dir/"}."
    shasum -a 256 "$program" | cut -d ' ' -f 1
  done
}

build_battle() {
  local version="$1" desktop_tag="$2" tag="v$1" release="battle-v$1" dir="$work/$battle" subject json state built_on
  json="$(release_json "$releases_repo" "$release")"
  state="$(state_of "$json")"
  # A draft a build left without all its files is built again, which finishes it.
  if [ "$state" = draft ] &&
    [ "$(jq -r '.assets[].name' <<<"$json" | grep -c "^Formiga-Battle-$version-" || true)" -ne "$files_per_release" ]; then
    state=""
  fi
  if [ -z "$state" ] && ! tag_exists "$battle" "$tag"; then
    clone "$battle"
    grep -qF "## [$version]" "$dir/CHANGELOG.md" ||
      fail "$battle's CHANGELOG.md has no section for $version yet. Merge it first."
    (cd "$dir" && scripts/set-version.sh "$version" "$desktop_tag" && scripts/set-version.sh --check)
    subject="Take Desktop's $desktop_tag and release $version"
    if ! git -C "$dir" diff --quiet; then
      git -C "$dir" commit --quiet -am "$subject"
      git -C "$dir" push --quiet origin HEAD:main ||
        fail "Could not push to $battle. Give RELEASE_TOKEN write access to its contents, or run its scripts/set-version.sh $version $desktop_tag, merge that, tag it $tag, and run this again."
    fi
    tag_release "$battle" "$tag" "$subject"
  fi
  # A tag made by hand, or a release built from one before, must be built on the same Desktop as
  # the rest of the release.
  built_on="$(gh api -H "Accept: application/vnd.github.raw" "repos/$owner/$battle/contents/Cargo.toml?ref=$tag" |
    sed -n 's/.*Formiga-Desktop", tag = "\(v[^"]*\)".*/\1/p' | sort -u)"
  [ "$built_on" = "$desktop_tag" ] ||
    fail "$battle's $tag is built on Desktop's ${built_on:-unknown tag}, not $desktop_tag."
  if [ -z "$state" ]; then
    run_battle_build "$version"
    json="$(release_json "$releases_repo" "$release")"
    [ "$(state_of "$json")" = draft ] || fail "$battle $version was not published as a draft."
    state=draft
  fi
  check_files "$releases_repo" "$release" Formiga-Battle "$json"
  say "$battle $version is a $state release with all its files. Its programs' digests:"
  battle_digests "$version"
}

# Points the website's fallback downloads at the new releases. The page itself always asks GitHub
# for the newest public release; the fallback is what it offers when GitHub cannot be reached.
ship_site() {
  local desktop_version="$1" hill="$2" home="$3" battle_version="$4" dir="$work/$site" branch="release/v$1" names digests
  clone "$site"
  if git -C "$dir" ls-remote --exit-code --heads origin "$branch" >/dev/null; then
    git -C "$dir" fetch --quiet origin "$branch"
    git -C "$dir" merge --quiet --squash "origin/$branch" ||
      fail "$site's $branch no longer merges cleanly into main. Bring main into it, then run this again."
  fi
  node "$here/site-downloads.mjs" "$dir/assets/js/config.js" \
    "desktop=$desktop_version" ${hill:+"hill=$hill"} ${home:+"home=$home"} ${battle_version:+"battle=$battle_version"}
  if [ -n "$battle_version" ]; then
    digests="$(battle_digests "$battle_version")"
    # shellcheck disable=SC2086 # one digest a word
    node "$here/battle-builds.mjs" "$dir/lib/battle-builds.mjs" "$battle_version" $digests
  fi
  git -C "$dir" add -A
  if git -C "$dir" diff --cached --quiet; then
    say "$site already offers these releases."
    return
  fi
  names="Desktop $desktop_version${hill:+, Hill $hill}${home:+, Home $home}${battle_version:+, Battle $battle_version}"
  git -C "$dir" commit --quiet -m "Offer $names"
  git -C "$dir" push --quiet origin HEAD:main
  say "$site now offers $names."
}

command="${1:-}"
desktop_version="${2:-}"
if ! [[ "$command" =~ ^(build|ship)$ ]] || [ -z "$desktop_version" ]; then
  fail "usage: $(basename "$0") build|ship <desktop> [<hill>] [<home>] [<battle>]"
fi
versions=("${3:-}" "${4:-}")
battle_version="${5:-}"
check_version "$desktop_version"
for v in "${versions[@]}" "$battle_version"; do [ -z "$v" ] || check_version "$v"; done
: "${GH_TOKEN:?GH_TOKEN must be set}"

# The expansions given a version: repository, download name and version.
chosen=()
for i in "${!expansions[@]}"; do
  [ -z "${versions[$i]}" ] || chosen+=("${expansions[$i]} ${versions[$i]}")
done

if [ "$command" = build ]; then
  build_desktop "$desktop_version"
  for entry in "${chosen[@]}"; do
    read -r repo prefix version <<<"$entry"
    build_expansion "$repo" "$prefix" "$version" "v$desktop_version"
  done
  [ -z "$battle_version" ] || build_battle "$battle_version" "v$desktop_version"
  say "Every draft is ready to try. Run ship with the same versions to make them public."
  exit 0
fi

# Ship: check every draft is whole before making any of them public, so a half-built set never
# goes out.
releases=("$desktop Formiga v$desktop_version")
for entry in "${chosen[@]}"; do
  read -r repo prefix version <<<"$entry"
  releases+=("$repo $prefix v$version")
done
[ -z "$battle_version" ] || releases+=("$releases_repo Formiga-Battle battle-v$battle_version")
states=()
for entry in "${releases[@]}"; do
  read -r repo prefix tag <<<"$entry"
  json="$(release_json "$repo" "$tag")"
  state="$(state_of "$json")"
  [ -n "$state" ] || fail "$repo has no $tag release. Run build first."
  states+=("$state")
  check_files "$repo" "$tag" "$prefix" "$json"
done
for i in "${!releases[@]}"; do
  read -r repo prefix tag <<<"${releases[$i]}"
  if [ "${states[$i]}" = draft ]; then
    gh_on "$repo" release edit "$tag" -R "$owner/$repo" --draft=false --latest >/dev/null
    say "$repo $tag is public."
  else
    say "$repo $tag was already public."
  fi
done
ship_site "$desktop_version" "${versions[0]}" "${versions[1]}" "$battle_version"
