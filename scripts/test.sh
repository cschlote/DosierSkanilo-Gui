#!/usr/bin/env sh
set -eu

DUB_COMPILER="${DUB_COMPILER:-ldc2}"

echo "[test] compiler: ${DUB_COMPILER}"
# No unit test suite yet; compile as smoke test.
dub build --compiler="${DUB_COMPILER}" -b=debug -c=application
