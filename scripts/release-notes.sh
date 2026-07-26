#!/bin/sh

set -eu

version="${1:?Expected a release version}"
changelog_file="${2:-CHANGELOG.md}"

if [ ! -f "$changelog_file" ]; then
    echo "Missing $changelog_file" >&2
    exit 66
fi

awk -v version="$version" '
    $0 ~ "^##[[:space:]]+\\[?v?" version "\\]?([[:space:]]|$)" {
        found = 1
        next
    }
    found && /^##[[:space:]]/ {
        exit
    }
    found {
        print
    }
    END {
        if (!found) {
            exit 67
        }
    }
' "$changelog_file"
