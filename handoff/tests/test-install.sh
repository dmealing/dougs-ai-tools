#!/bin/sh
# Tests for ../install.sh. The cases are shared with the other tools and live
# in ../../lib/test-install-skill.sh; every one runs against a throwaway config
# directory, so nothing under the real Claude Code configuration is touched.
#
# Run: sh handoff/tests/test-install.sh

set -u

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)
root=$(dirname -- "$here")
repo=$(dirname -- "$root")

# The four variables are read by the sourced cases.
# shellcheck disable=SC2034
{
	installer="$root/install.sh"
	skill_name=handoff
	skill_src="$root/skills/handoff"
	skill_files='SKILL.md reference.md'
}

# shellcheck source=/dev/null
. "$repo/lib/test-helpers.sh"
# shellcheck source=/dev/null
. "$repo/lib/test-install-skill.sh"

finish install
