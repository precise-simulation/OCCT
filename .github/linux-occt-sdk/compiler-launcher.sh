#!/usr/bin/env bash
set -euo pipefail

compiler="$1"
shift

exec "$compiler" \
  -ffile-prefix-map=/work/src=/usr/src/opencascade \
  -fdebug-prefix-map=/work/src=/usr/src/opencascade \
  -fmacro-prefix-map=/work/src=/usr/src/opencascade \
  -ffile-prefix-map=/work/build=/usr/src/opencascade-build \
  -fdebug-prefix-map=/work/build=/usr/src/opencascade-build \
  "$@"
