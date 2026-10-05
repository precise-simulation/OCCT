#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 <sdk-prefix> <output-archive>" >&2
  exit 2
fi
: "${SOURCE_DATE_EPOCH:?SOURCE_DATE_EPOCH is required}"

prefix="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
archive="$2"
parent="$(dirname "$prefix")"
name="$(basename "$prefix")"

command -v gtar >/dev/null
command -v gzip >/dev/null
mkdir -p "$(dirname "$archive")"
export COPYFILE_DISABLE=1

gtar \
  --sort=name \
  --format=posix \
  --pax-option=delete=atime,delete=ctime \
  --mtime="@${SOURCE_DATE_EPOCH}" \
  --owner=0 \
  --group=0 \
  --numeric-owner \
  -C "$parent" \
  -cf - \
  "$name" | gzip -n > "$archive"

(
  cd "$(dirname "$archive")"
  shasum -a 256 "$(basename "$archive")" > "$(basename "$archive").sha256"
  shasum -a 256 -c "$(basename "$archive").sha256"
)
