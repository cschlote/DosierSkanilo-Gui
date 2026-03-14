#!/usr/bin/env sh
set -eu

DUB_COMPILER="${DUB_COMPILER:-ldc2}"
ADRDOX_COMPILER="${ADRDOX_COMPILER:-}"

if [ -z "${ADRDOX_COMPILER}" ]; then
  if command -v gdc >/dev/null 2>&1; then
    ADRDOX_COMPILER="gdc"
  else
    ADRDOX_COMPILER="${DUB_COMPILER}"
  fi
fi

mkdir -p public

# Build API docs from the GUI source tree.
dub fetch adrdox
dub run adrdox --compiler="${ADRDOX_COMPILER}" -- source -o public -i --skeleton "$PWD/docs/skeleton.html"
cp -f ./docs/dosierskanilo-icon.svg ./public/dosierskanilo-icon.svg

echo "[build-docs] done"
