#!/bin/zsh
set -euo pipefail

project_dir=${0:A:h:h:h}
renderer="$(brew --prefix librsvg)/bin/rsvg-convert"
source="$project_dir/Resources/Icons/Source/BrandAction.svg"
rendered="$project_dir/Resources/Icons/Rendered/brand-action.png"
installed="$project_dir/layout/Library/Application Support/WCLiquidGlass/Icons/brand-action.png"

"$renderer" --width 1024 --height 1024 --output "$rendered" "$source"
cp "$rendered" "$installed"
