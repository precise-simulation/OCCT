#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 3 || $# -gt 4 ]]; then
  echo "usage: $0 <artifact-dir> <shared|static> <arm64|x86_64> [native-consumer-arch]" >&2
  exit 2
fi

artifact_dir="$(cd "$1" && pwd)"
linkage="$2"
artifact_arch="$3"
consumer_arch="${4:-}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

shopt -s nullglob
archives=("$artifact_dir"/*.tar.gz)
checksums=("$artifact_dir"/*.tar.gz.sha256)
shopt -u nullglob
if [[ ${#archives[@]} -ne 1 ]]; then
  echo "expected exactly one SDK archive in $artifact_dir" >&2
  exit 1
fi
if [[ ${#checksums[@]} -ne 1 ]]; then
  echo "expected exactly one SDK checksum in $artifact_dir" >&2
  exit 1
fi
archive="${archives[0]}"
checksum="${checksums[0]}"
if [[ "$checksum" != "$archive.sha256" ]]; then
  echo "checksum filename does not match archive" >&2
  exit 1
fi
(
  cd "$artifact_dir"
  shasum -a 256 -c "$(basename "$checksum")"
)

sdk_name="$(basename "$archive" .tar.gz)"
extract_parent="${RUNNER_TEMP:?RUNNER_TEMP is required}/validate-$linkage-$artifact_arch-$RANDOM"
mkdir -p "$extract_parent"
export COPYFILE_DISABLE=1
gtar -xzf "$archive" -C "$extract_parent"
prefix="$extract_parent/$sdk_name"

python3 "$script_dir/sdk_tools.py" validate-prefix \
  --prefix "$prefix" \
  --linkage "$linkage" \
  --architecture "$artifact_arch" \
  --deployment-target 13.0

if [[ -n "$consumer_arch" ]]; then
  bash "$script_dir/run-consumer.sh" "$prefix" "$extract_parent/consumer" "$linkage" "$consumer_arch"
  rm -rf "$extract_parent/consumer"
  relocated_parent="${extract_parent}-relocated"
  mkdir -p "$relocated_parent"
  mv "$prefix" "$relocated_parent/$sdk_name"
  prefix="$relocated_parent/$sdk_name"
  python3 "$script_dir/sdk_tools.py" validate-prefix \
    --prefix "$prefix" \
    --linkage "$linkage" \
    --architecture "$artifact_arch" \
    --deployment-target 13.0
  bash "$script_dir/run-consumer.sh" "$prefix" "$relocated_parent/consumer" "$linkage" "$consumer_arch"
fi
