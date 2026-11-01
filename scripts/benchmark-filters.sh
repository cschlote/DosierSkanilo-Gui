#!/usr/bin/env sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "${ROOT_DIR}"

DC=${DC:-ldc2}
printf '%s\n' "[benchmark] building release filter benchmark with ${DC}"
DC="${DC}" dub run --config=benchmark --compiler="${DC}" -b=release -- "$@"
