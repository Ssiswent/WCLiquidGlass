#!/bin/sh

set -eu

package_file="${1:?Expected a package file path}"
upload_url="${WCLIQUIDGLASS_UPLOAD_URL:-http://192.168.1.145:8088}"
upload_path="${WCLIQUIDGLASS_UPLOAD_PATH:-/Plugins/}"

if [ "${GITHUB_ACTIONS:-}" = "true" ] || [ "${WCLIQUIDGLASS_SKIP_UPLOAD:-}" = "1" ]; then
    echo "Skipping local HTTP package upload"
    exit 0
fi

if [ ! -f "$package_file" ]; then
    echo "Package file not found: $package_file" >&2
    exit 66
fi

upload_url=${upload_url%/}
package_name=$(basename "$package_file")

curl --fail --show-error --silent --connect-timeout 5 --max-time 120 \
    -F "path=$upload_path" \
    -F "files[]=@$package_file;filename=$package_name" \
    "$upload_url/upload"
printf '\nUploaded: %s%s\n' "$upload_path" "$package_name"
