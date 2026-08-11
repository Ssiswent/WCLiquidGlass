#!/bin/sh

set -eu

upload_url="${WCLIQUIDGLASS_UPLOAD_URL:-http://192.168.1.145:8088}"
upload_path="${WCLIQUIDGLASS_UPLOAD_PATH:-/Plugins/}"

upload_url=${upload_url%/}

if [ "${1:-}" = "--check" ]; then
    curl --show-error --silent --connect-timeout 3 --max-time 8 \
        "$upload_url/" >/dev/null
    exit 0
fi

if [ "${GITHUB_ACTIONS:-}" = "true" ] || [ "${WCLIQUIDGLASS_SKIP_UPLOAD:-}" = "1" ]; then
    echo "Skipping local HTTP package upload"
    exit 0
fi

package_file="${1:?Expected a package file path}"

if [ ! -f "$package_file" ]; then
    echo "Package file not found: $package_file" >&2
    exit 66
fi

package_name=$(basename "$package_file")
remote_path="${upload_path%/}/$package_name"
remote_file="$upload_url/download?path=$remote_path"
remote_copy=$(mktemp)
trap 'rm -f "$remote_copy"' EXIT

remote_status=$(curl --show-error --silent --output "$remote_copy" --write-out '%{http_code}' \
    --get --data-urlencode "path=$remote_path" \
    --connect-timeout 3 --max-time 20 "$upload_url/download" || true)

case "$remote_status" in
    200)
        local_sha=$(shasum -a 256 "$package_file" | awk '{print $1}')
        remote_sha=$(shasum -a 256 "$remote_copy" | awk '{print $1}')
        if [ "$local_sha" = "$remote_sha" ]; then
            printf 'Already uploaded: %s%s\n' "$upload_path" "$package_name"
            exit 0
        fi
        echo "Refusing to upload a different package over existing $remote_path. Bump Version first." >&2
        exit 73
        ;;
    404)
        ;;
    *)
        echo "Could not verify existing package at $remote_file (HTTP ${remote_status:-transport-error})." >&2
        exit 74
        ;;
esac

curl --fail --show-error --silent --connect-timeout 5 --max-time 120 \
    -F "path=$upload_path" \
    -F "files[]=@$package_file;filename=$package_name" \
    "$upload_url/upload"
printf '\nUploaded: %s%s\n' "$upload_path" "$package_name"
