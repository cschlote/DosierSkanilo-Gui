#!/usr/bin/env sh
set -eu

# Placeholder lint stage. Keep non-failing until dedicated linters are added.
echo "[lint] no dedicated linter configured yet"
dub describe >/dev/null
