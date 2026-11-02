#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 <tag> <expected-commit>" >&2
  exit 2
fi

tag="$1"
expected="$2"
api_version="2026-03-10"
object_json="$(gh api -H "X-GitHub-Api-Version: ${api_version}" "repos/${GITHUB_REPOSITORY}/git/ref/tags/${tag}")"
object_type="$(jq -r '.object.type' <<<"$object_json")"
object_sha="$(jq -r '.object.sha' <<<"$object_json")"

for _ in 1 2 3 4 5; do
  if [[ "$object_type" == "commit" ]]; then
    break
  fi
  if [[ "$object_type" != "tag" ]]; then
    echo "tag $tag resolves to unsupported object type: $object_type" >&2
    exit 1
  fi
  object_json="$(gh api -H "X-GitHub-Api-Version: ${api_version}" "repos/${GITHUB_REPOSITORY}/git/tags/${object_sha}")"
  object_type="$(jq -r '.object.type' <<<"$object_json")"
  object_sha="$(jq -r '.object.sha' <<<"$object_json")"
done

if [[ "$object_type" != "commit" || "$object_sha" != "$expected" ]]; then
  echo "tag $tag resolves to $object_type $object_sha, expected commit $expected" >&2
  exit 1
fi
echo "$object_sha"
