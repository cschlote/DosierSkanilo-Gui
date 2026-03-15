#!/usr/bin/env sh
set -eu

DUB_COMPILER="${DUB_COMPILER:-ldc2}"
LST_DIR="build/coverage/lst"

coverage_counts() {
	awk -F'|' '
		{
			prefix = $1
			gsub(/^[[:space:]]+|[[:space:]]+$/, "", prefix)
			if (prefix ~ /^[0-9]+$/) {
				total += 1
				if (prefix != "0" && prefix != "0000000") {
					covered += 1
				}
			}
		}
		END {
			printf "%d %d\n", covered + 0, total + 0
		}
	' "$1"
}

coverage_percent() {
	covered="$1"
	total="$2"
	awk -v covered="$covered" -v total="$total" 'BEGIN {
		if (total == 0) {
			printf "0.00"
		} else {
			printf "%.2f", (covered * 100.0) / total
		}
	}'
}

echo "[test] compiler: ${DUB_COMPILER}"
echo "[test] running unit test suite with coverage"

rm -rf build/coverage
rm -f ./*.lst
find . -maxdepth 1 -type l -name '*.lst' -delete

dub test --compiler="${DUB_COMPILER}" -b=unittest-cov

mkdir -p "${LST_DIR}"

find . -maxdepth 1 -type f -name '*.lst' -exec mv -f {} "${LST_DIR}"/ \;

# VS Code DCode coverage overlays expect .lst files in workspace root.
# Keep canonical coverage files under build/coverage and expose source-only symlinks.
find "${LST_DIR}" -maxdepth 1 -type f -name 'source-*.lst' -exec ln -sfn {} ./ \;

total_covered=0
total_lines=0

for lst in ./${LST_DIR}/source-*.lst; do
	[ -f "$lst" ] || continue

	counts=$(coverage_counts "$lst")
	covered=$(printf "%s" "$counts" | cut -d' ' -f1)
	lines=$(printf "%s" "$counts" | cut -d' ' -f2)
	percent=$(coverage_percent "$covered" "$lines")

	pretty_path=$(printf "%s" "$lst" | sed 's#^\./build/coverage/lst/source-#source/#; s#-#/#g; s#\.lst$#.d#')
	printf '[coverage] FILE %s %s/%s (%s%%)\n' "$pretty_path" "$covered" "$lines" "$percent"

	total_covered=$((total_covered + covered))
	total_lines=$((total_lines + lines))
done

total_percent=$(coverage_percent "$total_covered" "$total_lines")
printf '[coverage] TOTAL %s/%s (%s%%)\n' "$total_covered" "$total_lines" "$total_percent" | tee build/coverage/summary.txt
