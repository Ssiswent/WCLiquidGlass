#!/bin/sh

set -eu

control_file="control"
mode="${1:-}"

if [ "$mode" != "--next" ] && [ "$mode" != "--apply" ]; then
    echo "Usage: $0 --next | --apply" >&2
    exit 64
fi

current_version=$(sed -n 's/^Version:[[:space:]]*//p' "$control_file")
base_version=${current_version%%~*}
old_ifs=$IFS
IFS=.
set -- $base_version
IFS=$old_ifs

if [ "$#" -ne 3 ]; then
    echo "Expected Version in $control_file to use MAJOR.MINOR.PATCH or a legacy ~suffix; found: $current_version" >&2
    exit 65
fi

for component in "$@"; do
    case "$component" in
        ''|*[!0-9]*)
            echo "Expected Version in $control_file to use numeric MAJOR.MINOR.PATCH or a legacy ~suffix; found: $current_version" >&2
            exit 65
            ;;
    esac
done

next_version="$1.$2.$(( $3 + 1 ))"

if [ "$mode" = "--next" ]; then
    printf '%s\n' "$next_version"
    exit 0
fi

temporary_control=$(mktemp "${control_file}.XXXXXX")
trap 'rm -f "$temporary_control"' EXIT HUP INT TERM
awk -v version="$next_version" '
    /^Version:[[:space:]]*/ {
        print "Version: " version
        next
    }
    { print }
' "$control_file" > "$temporary_control"
mv "$temporary_control" "$control_file"
trap - EXIT HUP INT TERM
printf 'Version: %s\n' "$next_version"
