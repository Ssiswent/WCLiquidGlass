#!/bin/sh

set -eu

usage() {
    echo "Usage: $0 --tag VERSION | --channel VERSION | --validate-tag VERSION TAG" >&2
    exit 64
}

[ "$#" -ge 2 ] || usage

mode=$1
version=$2

validate_version() {
    base=${version%%~*}
    suffix=
    case "$version" in
        *'~'*)
            suffix=${version#*~}
            case "$suffix" in
                ''|*'~'*|*[!0-9A-Za-z.-]*|.*|*.)
                    echo "Invalid prerelease package version: $version" >&2
                    exit 65
                    ;;
            esac
            ;;
    esac

    printf '%s\n' "$base" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || {
        echo "Expected MAJOR.MINOR.PATCH or MAJOR.MINOR.PATCH~PRERELEASE; found: $version" >&2
        exit 65
    }
}

validate_version
base=${version%%~*}
suffix=
case "$version" in
    *'~'*) suffix=${version#*~} ;;
esac

case "$mode" in
    --tag)
        if [ -n "$suffix" ]; then
            printf 'v%s-%s\n' "$base" "$suffix"
        else
            printf 'v%s\n' "$base"
        fi
        ;;
    --channel)
        if [ -n "$suffix" ]; then
            printf '%s\n' prerelease
        else
            printf '%s\n' stable
        fi
        ;;
    --validate-tag)
        [ "$#" = 3 ] || usage
        expected_tag=$("$0" --tag "$version")
        if [ "$3" != "$expected_tag" ]; then
            echo "Release tag must be $expected_tag for package version $version" >&2
            exit 66
        fi
        ;;
    *)
        usage
        ;;
esac
