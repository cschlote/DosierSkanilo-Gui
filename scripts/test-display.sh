#!/usr/bin/env sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "${ROOT_DIR}"

DC=${DC:-ldc2}
LOGIN_DIR=$(mktemp -d "${TMPDIR:-/tmp}/dosierskanilo-gui-display.XXXXXX")
XVFB_PID=""
cleanup() {
	if [ -n "${XVFB_PID}" ]; then
		kill "${XVFB_PID}" >/dev/null 2>&1 || true
	fi
	rm -rf "${LOGIN_DIR}"
}
trap cleanup EXIT

if command -v xvfb-run >/dev/null 2>&1; then
	run_with_display() {
		xvfb-run -a -s "-screen 0 1280x1024x24" "$@"
	}
elif command -v Xvfb >/dev/null 2>&1; then
	DISPLAY_NUMBER=99
	Xvfb ":${DISPLAY_NUMBER}" -screen 0 1280x1024x24 >"${LOGIN_DIR}/xvfb.log" 2>&1 &
	XVFB_PID=$!
	export DISPLAY=":${DISPLAY_NUMBER}"
	sleep 1
	run_with_display() {
		"$@"
	}
elif [ -n "${DISPLAY:-}" ]; then
	run_with_display() {
		"$@"
	}
else
	printf '%s\n' "[display-test] no DISPLAY and no X server is available; skipping."
	exit 0
fi

printf '%s\n' "[display-test] running unit suite with display-backed checks"
run_with_display env DOSIER_GUI_TABLE_SCROLL_TEST=1 DC="${DC}" \
	dub test --build=unittest --compiler="${DC}" -- -v

printf '%s\n' "[display-test] building the GUI for the startup smoke test"
DC="${DC}" dub build --compiler="${DC}"

backend_dir="${ROOT_DIR}/../DosierSkanilo"
fixture="${backend_dir}/test/json_file_v2.json"
if [ -f "${fixture}" ]; then
	printf '%s\n' "[display-test] running GUI startup self-test on a JSON catalog"
	run_with_display env HOME="${LOGIN_DIR}" XDG_CONFIG_HOME="${LOGIN_DIR}/config" \
		./build/bin/dosierskanilo-gui \
		--self-test --self-test-delay 700 "${fixture}"
	mkdir -p "${LOGIN_DIR}/.config/dosierskanilo-gui"
	cat > "${LOGIN_DIR}/.config/dosierskanilo-gui/state.json" <<'JSON'
{"windowWidth":1200,"windowHeight":800,"splitPositionHorizontal":5000,"splitPositionVertical":5000,"splitPositionPreview":5000,"hasSplitPositionPreview":true}
JSON
	printf '%s\n' "[display-test] verifying restored splitter positions are usable"
	run_with_display env HOME="${LOGIN_DIR}" XDG_CONFIG_HOME="${LOGIN_DIR}/config" \
		./build/bin/dosierskanilo-gui \
		--self-test --self-test-check-splitter \
		--self-test-delay 700 "${fixture}"

	printf '%s\n' "[display-test] running a JSON analyze operation in memory"
	run_with_display env HOME="${LOGIN_DIR}" XDG_CONFIG_HOME="${LOGIN_DIR}/config" \
		./build/bin/dosierskanilo-gui \
		--self-test --self-test-operation analyze --self-test-save \
		--self-test-delay 1200 "${fixture}"
else
	printf '%s\n' "[display-test] catalog fixture not found; skipping JSON smoke test."
fi

if [ -d "${backend_dir}" ]; then
	printf '%s\n' "[display-test] building the backend CLI for a repository fixture"
	(cd "${backend_dir}" && DC="${DC}" dub build --compiler="${DC}")
	repository_dir="${LOGIN_DIR}/repository"
	mkdir -p "${repository_dir}"
	printf 'payload\n' > "${repository_dir}/sample.txt"
	"${backend_dir}/build/bin/dosierskanilo" init "${repository_dir}" >/dev/null
	"${backend_dir}/build/bin/dosierskanilo" scan "${repository_dir}" >/dev/null
	printf '%s\n' "[display-test] running GUI startup self-test on a repository"
	run_with_display env HOME="${LOGIN_DIR}" XDG_CONFIG_HOME="${LOGIN_DIR}/config" \
		./build/bin/dosierskanilo-gui \
		--self-test --self-test-delay 1200 "${repository_dir}"
	for operation in scan metadata analyze synthetic-pause synthetic-cancel; do
		printf '%s\n' "[display-test] running Tools ${operation} operation"
		run_with_display env HOME="${LOGIN_DIR}" XDG_CONFIG_HOME="${LOGIN_DIR}/config" \
			./build/bin/dosierskanilo-gui \
			--self-test --self-test-operation "${operation}" \
			--self-test-delay 1200 "${repository_dir}"
	done
else
	printf '%s\n' "[display-test] backend checkout not found; skipping repository smoke test."
fi

printf '%s\n' "[display-test] passed"
