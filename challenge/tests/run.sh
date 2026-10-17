#!/bin/sh
# Runs every test for the challenge sub-project.
#
# Run from anywhere: sh challenge/tests/run.sh
# Every tool at once, with the shared code in lib/: sh tests/run.sh

set -u

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)

# shellcheck source=/dev/null
. "$here/../../lib/run-suite.sh"
run_suite "$here" "$here/../install.sh" "$here/../skills/challenge/challenge-common.sh" \
	"$here/../skills/challenge/challenge-log.sh" "$here/../skills/challenge/challenge-run.sh"
