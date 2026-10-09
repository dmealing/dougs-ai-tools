#!/bin/sh
# Runs every test for the pickup sub-project.
#
# Run from anywhere: sh pickup/tests/run.sh
# Every tool at once, with the shared code in lib/: sh tests/run.sh

set -u

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)

status=0
for test_file in "$here/test-list-handoffs.sh" "$here/test-install.sh" "$here/test-shipped-files.sh"; do
	printf '== %s\n' "$(basename -- "$test_file")"
	sh "$test_file" || status=1
done

if command -v shellcheck >/dev/null 2>&1; then
	printf '== shellcheck\n'
	if shellcheck "$here/../install.sh" "$here/../skills/pickup/list-handoffs.sh" "$here"/*.sh; then
		printf 'ok   - shellcheck clean\n'
	else
		status=1
	fi
else
	printf '== shellcheck not found; skipped\n'
fi

exit "$status"
