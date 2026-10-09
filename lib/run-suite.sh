#!/bin/sh
# Shared by every tool's tests/run.sh: source it, do not run it.

# run_suite <tests folder> [<file to lint>...]: runs every test-*.sh in the
# folder, then shellcheck, when it is installed, over the folder's scripts and
# the files named. Returns 0 when everything passed, else 1.
run_suite() {
	suite_dir=$1
	shift
	suite_status=0
	for test_file in "$suite_dir"/test-*.sh; do
		printf '== %s\n' "$(basename -- "$test_file")"
		sh "$test_file" || suite_status=1
	done

	if command -v shellcheck >/dev/null 2>&1; then
		printf '== shellcheck\n'
		if shellcheck "$@" "$suite_dir"/*.sh; then
			printf 'ok   - shellcheck clean\n'
		else
			suite_status=1
		fi
	else
		printf '== shellcheck not found; skipped\n'
	fi
	return "$suite_status"
}
