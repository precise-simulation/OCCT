#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "usage: $0 <sdk-prefix> <build-dir> <shared|static>" >&2
  exit 2
fi

sdk_prefix="$(readlink -f "$1")"
build_dir="$2"
linkage="$3"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
consumer_src="$script_dir/consumer"

rm -rf "$build_dir"
mkdir -p "$build_dir"

cmake \
  -S "$consumer_src" \
  -B "$build_dir" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_FIND_PACKAGE_NO_PACKAGE_REGISTRY=ON \
  -DCMAKE_FIND_USE_PACKAGE_REGISTRY=OFF \
  -DOpenCASCADE_DIR="$sdk_prefix/lib/cmake/opencascade"
cmake --build "$build_dir" --parallel --verbose

consumer="$build_dir/occt_sdk_consumer"
test -x "$consumer"

if [[ "$linkage" == "static" ]]; then
  if readelf -d "$consumer" | grep -Eq 'NEEDED.*libTK[^]]*\.so'; then
    echo "static consumer unexpectedly depends on a shared OCCT toolkit" >&2
    readelf -d "$consumer" >&2
    exit 1
  fi
fi

env -u CASROOT -u THIRDPARTY_DIR -u CSF_OCCTLibPath -u CSF_OCCTResourcePath \
  bash -c 'set -eo pipefail; source "$1/bin/env.sh"; set -u; cd "$2"; exec "$3"' \
  _ "$sdk_prefix" "$build_dir" "$consumer"
