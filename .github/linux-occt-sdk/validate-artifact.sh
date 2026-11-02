#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 || ( "$2" != "shared" && "$2" != "static" ) ]]; then
  echo "usage: $0 <artifact-directory> <shared|static>" >&2
  exit 2
fi

artifact_dir="$(readlink -f "$1")"
linkage="$2"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mapfile -t archives < <(find "$artifact_dir" -maxdepth 1 -type f -name '*.tar.gz' -print)
if [[ ${#archives[@]} -ne 1 ]]; then
  echo "expected exactly one SDK archive in $artifact_dir" >&2
  exit 1
fi
archive="${archives[0]}"
checksum="$archive.sha256"
test -f "$checksum"
(
  cd "$artifact_dir"
  sha256sum -c "$(basename "$checksum")"
)

sdk_name="$(basename "$archive" .tar.gz)"
extract_parent="${RUNNER_TEMP:-/tmp}/occt-sdk-${linkage}-${RANDOM}"
mkdir -p "$extract_parent"
tar -xzf "$archive" -C "$extract_parent"
prefix="$extract_parent/$sdk_name"

python3 "$script_dir/sdk_tools.py" validate-prefix --prefix "$prefix" --linkage "$linkage"
bash "$script_dir/run-consumer.sh" "$prefix" "$extract_parent/consumer" "$linkage"

relocated_parent="${extract_parent}-relocated"
mkdir -p "$relocated_parent"
mv "$prefix" "$relocated_parent/$sdk_name"
prefix="$relocated_parent/$sdk_name"
python3 "$script_dir/sdk_tools.py" validate-prefix --prefix "$prefix" --linkage "$linkage"
bash "$script_dir/run-consumer.sh" "$prefix" "$relocated_parent/consumer" "$linkage"
