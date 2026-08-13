#!/bin/sh

set -eu

project_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$project_root"

exec make clean package FINALPACKAGE=1 WCLIQUIDGLASS_DISTRIBUTE=1
