#!/bin/sh

set -eu

usage() {
    echo "Usage: $0 --tag VERSION | --validate-tag VERSION TAG" >&2
    exit 64
}

validate_version() {
    printf '%s\n' "$1" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || {
        echo "Expected MAJOR.MINOR.PATCH; found: $1" >&2
        exit 65
    }
}

[ "$#" -ge 2 ] || usage

case "$1" in
    --tag)
        [ "$#" = 2 ] || usage
        validate_version "$2"
        printf 'v%s\n' "$2"
        ;;
    --validate-tag)
        [ "$#" = 3 ] || usage
        validate_version "$2"
        if [ "$3" != "v$2" ]; then
            echo "Release tag must be v$2 for package version $2" >&2
            exit 66
        fi
        ;;
    *)
        usage
        ;;
esac
