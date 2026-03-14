#!/usr/bin/env sh
set -eu

./scripts/lint.sh
./scripts/build.sh
./scripts/test.sh

echo "[build-all] done"
