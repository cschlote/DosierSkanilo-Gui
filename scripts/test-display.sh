#!/usr/bin/env sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "${ROOT_DIR}"

DC=${DC:-ldc2}
LOGIN_DIR=$(mktemp -d "${TMPDIR:-/tmp}/dosierskanilo-gui-display.XXXXXX")
trap 'rm -rf "${LOGIN_DIR}"' EXIT

if command -v xvfb-run >/dev/null 2>&1; then
	run_with_display() {
		xvfb-run -a -s "-screen 0 1280x1024x24" "$@"
	}
elif [ -n "${DISPLAY:-}" ]; then
	run_with_display() {
		"$@"
	}
else
	printf '%s\n' "[display-test] no DISPLAY and xvfb-run is unavailable; skipping."
	exit 0
fi

printf '%s\n' "[display-test] running unit suite with display-backed checks"
run_with_display env DOSIER_GUI_TABLE_SCROLL_TEST=1 DC="${DC}" \
	dub test --build=unittest --compiler="${DC}" -- -v

printf '%s\n' "[display-test] building the GUI for the startup smoke test"
DC="${DC}" dub build --compiler="${DC}"

fixture="${ROOT_DIR}/../DosierSkanilo/test/json_file_v2.json"
if [ -f "${fixture}" ]; then
	printf '%s\n' "[display-test] running GUI startup self-test"
	run_with_display env HOME="${LOGIN_DIR}" XDG_CONFIG_HOME="${LOGIN_DIR}/config" \
		G_DEBUG=fatal-warnings ./build/bin/dosierskanilo-gui \
		--self-test --self-test-delay 700 "${fixture}"
else
	printf '%s\n' "[display-test] catalog fixture not found; skipping startup smoke test."
fi

printf '%s\n' "[display-test] passed"
