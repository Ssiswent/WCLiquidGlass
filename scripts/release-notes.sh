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
            printf "## WCLiquidGlass %s\n\n", version
            print "- 自动构建包：未找到对应 CHANGELOG 条目。"
            print "- 详细改动请参阅仓库提交记录。"
        }
    }
' "$changelog_file"
