#!/usr/bin/env sh
set -eu

DUB_COMPILER="${DUB_COMPILER:-ldc2}"

echo "[build] compiler: ${DUB_COMPILER}"
dub build --compiler="${DUB_COMPILER}" -b=debug -c=application
