#!/bin/sh

set -eu

project_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$project_root"

exec make clean package FINALPACKAGE=1 WCLIQUIDGLASS_AUTO_BUMP=0 WCLIQUIDGLASS_DISTRIBUTE=1
