#!/bin/sh

set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project_root"

fail() {
    echo "Verification failed: $*" >&2
    exit 1
}

control_value() {
    sed -n "s/^$1:[[:space:]]*//p" control
}

package_id=$(control_value Package)
version=$(control_value Version)
architecture=$(control_value Architecture)

[ "$package_id" = "com.ssiswent.wcliquidglass" ] || fail "unexpected package id: $package_id"
[ -n "$version" ] || fail "control has no version"
[ "$architecture" = "iphoneos-arm64" ] || fail "unexpected architecture: $architecture"

for source_file in ./*.m ./*.xm ./*.c; do
    [ -f "$source_file" ] || continue
    source_name=${source_file#./}
    grep -Fq "$source_name" Makefile || fail "$source_name is missing from Makefile"
done

plist_output=$(plutil -p WCLiquidGlass.plist)
printf '%s\n' "$plist_output" | grep -Fq '"com.tencent.xin"' || fail "main WeChat bundle is missing from filter plist"
printf '%s\n' "$plist_output" | grep -Fq '"com.tencent.xin.sharetimeline"' || fail "share timeline bundle is missing from filter plist"

package_file=${1:-}
if [ -n "$package_file" ]; then
    [ -f "$package_file" ] || fail "package not found: $package_file"
    archive_members=$(ar -t "$package_file")
    printf '%s\n' "$archive_members" | grep -Fxq 'control.tar.gz' || fail "package has no control archive"
    printf '%s\n' "$archive_members" | grep -Fxq 'data.tar.lzma' || fail "package has no data archive"

    packaged_control=$(ar -p "$package_file" control.tar.gz | tar -xzOf - ./control)
    printf '%s\n' "$packaged_control" | grep -Fxq "Package: $package_id" || fail "package id differs from control"
    printf '%s\n' "$packaged_control" | grep -Fxq "Version: $version" || fail "package version differs from control"
    printf '%s\n' "$packaged_control" | grep -Fxq "Architecture: $architecture" || fail "package architecture differs from control"

    data_members=$(ar -p "$package_file" data.tar.lzma | tar -tJf -)
    printf '%s\n' "$data_members" | grep -Fxq 'var/jb/Library/MobileSubstrate/DynamicLibraries/WCLiquidGlass.dylib' || fail "rootless dylib is missing"
    printf '%s\n' "$data_members" | grep -Fxq 'var/jb/Library/MobileSubstrate/DynamicLibraries/WCLiquidGlass.plist' || fail "filter plist is missing"
fi

echo "Verified WCLiquidGlass $version${package_file:+ and $(basename "$package_file")}"
