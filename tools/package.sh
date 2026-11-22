#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(realpath -m "${1:-../artifacts}")
tag="${2:-v0.1.0}"
git rev-parse --verify "$tag^{commit}" >/dev/null
name=Bayline-Transport
if git show "$tag:game.conf" | grep -Fxq "title = LuanTTD"; then name=LuanTTD; fi
mkdir -p "$out"
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
git archive --format=zip --prefix=luanttd/ --output="$tmp/${name}-$tag.zip" "$tag"
git bundle create "$tmp/${name}-$tag.git.bundle" HEAD main "$tag"
git bundle verify "$tmp/${name}-$tag.git.bundle"
unzip -tq "$tmp/${name}-$tag.zip"
mv "$tmp/${name}-$tag.zip" "$tmp/${name}-$tag.git.bundle" "$out/"
(
  cd "$out"
  sha256sum "${name}-$tag.zip" "${name}-$tag.git.bundle" > "${name}-$tag.SHA256"
)
