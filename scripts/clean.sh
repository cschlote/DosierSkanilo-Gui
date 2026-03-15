#!/usr/bin/env sh
set -eu

rm -rf build
rm -rf .dub

# Coverage overlays can leave top-level .lst symlinks/files behind.
find . -maxdepth 1 -type f -name '*.lst' -delete
find . -maxdepth 1 -type l -name '*.lst' -delete

echo "[clean] removed build artifacts"
