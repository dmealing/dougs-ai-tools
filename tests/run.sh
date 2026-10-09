#!/bin/sh
# Runs every tool's tests, and lints the code the tools share.
#
# Run from anywhere: sh tests/run.sh

set -u

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)
repo=$(dirname -- "$here")

status=0
for tool in handoff pickup; do
	printf '==== %s\n' "$tool"
	sh "$repo/$tool/tests/run.sh" || status=1
done

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
