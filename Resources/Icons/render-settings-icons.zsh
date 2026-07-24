#!/bin/zsh
set -euo pipefail

project_dir=${0:A:h:h:h}
renderer="$(brew --prefix librsvg)/bin/rsvg-convert"
rendered="$project_dir/Resources/Icons/Rendered"
icons=(menu size compact-layout actions compatibility crash-capture crash-logs restore)

mode=${1:-dark}
if [[ "$mode" != "dark" && "$mode" != "all" ]]; then
  print -u2 "usage: ${0:t} [dark|all]"
  exit 64
fi

for icon in $icons; do
  if [[ "$mode" == "all" ]]; then
    "$renderer" --width 400 --height 400 --output "$rendered/$icon.png" "$project_dir/Resources/Icons/Source/$icon.svg"
  fi
  "$renderer" --width 400 --height 400 --output "$rendered/$icon-dark.png" "$project_dir/Resources/Icons/Source/dark/$icon.svg"
done

{
  print '/* Generated from Resources/Icons/Rendered. Do not edit by hand. */'
  xxd -i -n WCLiquidGlassIconBrand "$rendered/brand.png"
  xxd -i -n WCLiquidGlassIconMenu "$rendered/menu.png"
  xxd -i -n WCLiquidGlassIconSize "$rendered/size.png"
  xxd -i -n WCLiquidGlassIconCompactLayout "$rendered/compact-layout.png"
  xxd -i -n WCLiquidGlassIconActions "$rendered/actions.png"
  xxd -i -n WCLiquidGlassIconCompatibility "$rendered/compatibility.png"
  xxd -i -n WCLiquidGlassIconCrashCapture "$rendered/crash-capture.png"
  xxd -i -n WCLiquidGlassIconCrashLogs "$rendered/crash-logs.png"
  xxd -i -n WCLiquidGlassIconRestore "$rendered/restore.png"
  xxd -i -n WCLiquidGlassIconMenuDark "$rendered/menu-dark.png"
  xxd -i -n WCLiquidGlassIconSizeDark "$rendered/size-dark.png"
  xxd -i -n WCLiquidGlassIconCompactLayoutDark "$rendered/compact-layout-dark.png"
  xxd -i -n WCLiquidGlassIconActionsDark "$rendered/actions-dark.png"
  xxd -i -n WCLiquidGlassIconCompatibilityDark "$rendered/compatibility-dark.png"
  xxd -i -n WCLiquidGlassIconCrashCaptureDark "$rendered/crash-capture-dark.png"
  xxd -i -n WCLiquidGlassIconCrashLogsDark "$rendered/crash-logs-dark.png"
  xxd -i -n WCLiquidGlassIconRestoreDark "$rendered/restore-dark.png"
} > "$project_dir/WCLiquidGlassIconAssets.c"
