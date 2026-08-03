#!/bin/sh

set -eu

package_file="${1:?Expected a package file path}"
project_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$project_root"

if [ ! -f "$package_file" ]; then
    echo "Package file not found: $package_file" >&2
    exit 66
fi

if sh scripts/upload-package.sh --check >/dev/null 2>&1; then
    echo "Local HTTP service is available; distributing to the phone service."
    exec sh scripts/upload-package.sh "$package_file"
fi

echo "Local HTTP service is unavailable; publishing the package to GitHub Release."

package_version=$(sed -n 's/^Version:[[:space:]]*//p' control)
release_tag=$(scripts/release-version.sh --tag "$package_version")
scripts/release-version.sh --validate-tag "$package_version" "$release_tag"

if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "Refusing GitHub fallback from a dirty checkout. Commit and push the final source first." >&2
    exit 75
fi

head_commit=$(git rev-parse HEAD)
remote_main_commit=$(git ls-remote origin refs/heads/main | awk 'NR == 1 {print $1}')
if [ -z "$remote_main_commit" ] || [ "$remote_main_commit" != "$head_commit" ]; then
    echo "GitHub fallback requires the final source commit to be pushed to origin/main first." >&2
    exit 76
fi

if ! git rev-parse -q --verify "refs/tags/$release_tag^{}" >/dev/null && git ls-remote --exit-code --tags origin "refs/tags/$release_tag" >/dev/null 2>&1; then
    git fetch --quiet origin "refs/tags/$release_tag:refs/tags/$release_tag"
fi

if git rev-parse -q --verify "refs/tags/$release_tag^{}" >/dev/null; then
    local_tag_commit=$(git rev-parse "refs/tags/$release_tag^{}")
    if [ "$local_tag_commit" != "$head_commit" ]; then
        echo "Tag $release_tag does not point to the package source commit. Bump Version before distributing." >&2
        exit 77
    fi
else
    git tag -a "$release_tag" "$head_commit" -m "Release $package_version"
    git push origin "refs/tags/$release_tag"
    local_tag_commit=$head_commit
fi

remote_tag_commit=$(git ls-remote --tags origin "refs/tags/$release_tag^{}" | awk 'NR == 1 {print $1}')
if [ -z "$remote_tag_commit" ] || [ "$remote_tag_commit" != "$local_tag_commit" ]; then
    echo "Tag $release_tag is not pushed to origin with the package source commit." >&2
    exit 78
fi

release_notes_file=$(mktemp)
trap 'rm -f "$release_notes_file"' EXIT
scripts/release-notes.sh "$package_version" > "$release_notes_file"
release_title="WCLiquidGlass $package_version"
release_channel=$(scripts/release-version.sh --channel "$package_version")
release_state=--latest
if [ "$release_channel" = "prerelease" ]; then
    release_state=--prerelease
fi

if gh release view "$release_tag" >/dev/null 2>&1; then
    gh release upload "$release_tag" "$package_file" --clobber
    gh release edit "$release_tag" --title "$release_title" --notes-file "$release_notes_file" "$release_state"
else
    if ! gh release create "$release_tag" "$package_file" --target "$local_tag_commit" --title "$release_title" --notes-file "$release_notes_file" "$release_state"; then
        gh release upload "$release_tag" "$package_file" --clobber
        gh release edit "$release_tag" --title "$release_title" --notes-file "$release_notes_file" "$release_state"
    fi
fi

printf 'Published to GitHub Release: %s\n' "$release_tag"
