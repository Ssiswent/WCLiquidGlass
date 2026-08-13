#!/bin/sh

set -eu

package_file="${1:?Expected a package file path}"
project_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$project_root"

if [ ! -f "$package_file" ]; then
    echo "Package file not found: $package_file" >&2
    exit 66
fi

sh scripts/verify-project.sh "$package_file"

if sh scripts/upload-package.sh --check >/dev/null 2>&1; then
    echo "Local HTTP service is available; distributing to the phone service."
    exec sh scripts/upload-package.sh "$package_file"
fi

echo "Local HTTP service is unavailable; requesting GitHub Release fallback."

package_version=$(sed -n 's/^Version:[[:space:]]*//p' control)
release_tag=$(scripts/release-version.sh --tag "$package_version")
scripts/release-version.sh --validate-tag "$package_version" "$release_tag"
scripts/release-notes.sh "$package_version" >/dev/null

if [ -n "$(git status --porcelain)" ]; then
    echo "Refusing GitHub fallback from a dirty checkout. Commit and push the final source first." >&2
    exit 75
fi

git fetch --quiet origin main:refs/remotes/origin/main
head_commit=$(git rev-parse HEAD)
remote_main_commit=$(git rev-parse origin/main)
if [ "$remote_main_commit" != "$head_commit" ]; then
    echo "GitHub fallback requires HEAD to match origin/main." >&2
    exit 76
fi

if git rev-parse -q --verify "refs/tags/$release_tag^{}" >/dev/null || git ls-remote --exit-code --tags origin "refs/tags/$release_tag" >/dev/null 2>&1; then
    echo "Release tag $release_tag already exists. Bump Version before distributing." >&2
    exit 77
fi

git tag -a "$release_tag" "$head_commit" -m "Release $package_version"
if git push origin "refs/tags/$release_tag"; then
    :
else
    push_status=$?
    git tag -d "$release_tag" >/dev/null
    exit "$push_status"
fi
printf 'Pushed %s; GitHub Actions will build and publish the Release.\n' "$release_tag"
