#!/bin/sh
# Runs every tool's tests, and lints the code the tools share.
#
# Run from anywhere: sh tests/run.sh

set -u

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)
repo=$(dirname -- "$here")

status=0
for run_sh in "$repo"/*/tests/run.sh; do
	[ -f "$run_sh" ] || continue
	tool=${run_sh#"$repo/"}
	tool=${tool%%/*}
	printf '==== %s\n' "$tool"
	sh "$run_sh" || status=1
done

printf '==== plugins\n'
if command -v claude >/dev/null 2>&1; then
	for manifest in "$repo"/*/.claude-plugin/plugin.json; do
		[ -f "$manifest" ] || continue
		plugin_dir=$(dirname -- "$(dirname -- "$manifest")")
		if claude plugin validate --strict "$plugin_dir" >/dev/null 2>&1; then
			printf 'ok   - %s passes claude plugin validate --strict\n' "${plugin_dir#"$repo/"}"
		else
			printf 'FAIL - %s: claude plugin validate --strict\n' "${plugin_dir#"$repo/"}"
			status=1
		fi
	done
	if claude plugin validate --strict "$repo" >/dev/null 2>&1; then
		printf 'ok   - marketplace passes claude plugin validate --strict\n'
	else
		printf 'FAIL - marketplace: claude plugin validate --strict\n'
		status=1
	fi
else
	printf 'claude not found; plugin validation skipped\n'
fi

printf '==== shared\n'
if command -v shellcheck >/dev/null 2>&1; then
	if shellcheck "$repo"/lib/*.sh "$here"/*.sh; then
		printf 'ok   - shellcheck clean\n'
	else
		status=1
	fi
else
	printf 'shellcheck not found; skipped\n'
fi

if [ "$status" -eq 0 ]; then
	printf 'every suite passed\n'
else
	printf 'at least one suite failed\n'
fi
exit "$status"
