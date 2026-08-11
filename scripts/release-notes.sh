#!/bin/sh

set -eu

version="${1:?Expected a release version}"
changelog_file="${2:-CHANGELOG.md}"

scripts/release-version.sh --tag "$version" >/dev/null

if [ ! -f "$changelog_file" ]; then
    echo "Missing $changelog_file" >&2
    exit 66
fi

awk -v version="$version" '
    $0 == "## [" version "]" || index($0, "## [" version "] ") == 1 {
        found = 1
        next
    }
    found && /^##[[:space:]]/ {
        exit
    }
    found {
        print
        if ($0 ~ /[^[:space:]]/) content = 1
    }
    END {
        if (!found) {
            print "Missing CHANGELOG entry for " version > "/dev/stderr"
            exit 67
        }
        if (!content) {
            print "CHANGELOG entry for " version " is empty" > "/dev/stderr"
            exit 68
        }
    }
' "$changelog_file"
