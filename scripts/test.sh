#!/usr/bin/env sh
set -eu

DUB_COMPILER="${DUB_COMPILER:-ldc2}"

echo "[test] compiler: ${DUB_COMPILER}"
echo "[test] running unit test suite"
dub test --compiler="${DUB_COMPILER}" -b=debug
