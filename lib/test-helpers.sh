#!/bin/sh
# Shared by every tool's test scripts: source it, do not run it.
# Counts failures in $failures; finish() prints the verdict and sets the exit code.

failures=0

pass() { printf 'ok   - %s\n' "$1"; }

fail() {
	printf 'FAIL - %s\n' "$1"
	failures=$((failures + 1))
}

# check <description> <command...>: passes when the command succeeds.
check() {
	desc=$1
	shift
	if "$@"; then pass "$desc"; else fail "$desc"; fi
}

# finish <name of the suite>
finish() {
	if [ "$failures" -ne 0 ]; then
		printf '%s check(s) failed\n' "$failures"
		exit 1
	fi
	printf 'all %s checks passed\n' "$1"
}
