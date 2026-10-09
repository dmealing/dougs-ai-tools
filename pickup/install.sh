#!/bin/sh
# Install or remove the pickup skill for Claude Code without the plugin system.
#
# Copies skills/pickup/SKILL.md and skills/pickup/list-handoffs.sh from this
# folder to
#   ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills/pickup/
#
# The work is done by ../lib/install-skill.sh, which every tool in this
# repository shares, so run this from a full clone of the repository.
#
# POSIX sh; runs on macOS and Linux.

set -eu

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)
lib="$here/../lib/install-skill.sh"
if [ ! -f "$lib" ]; then
	printf 'install.sh: cannot find %s; run install.sh from a full clone of the repository\n' "$lib" >&2
	exit 1
fi

# The four variables are read by the sourced file.
# shellcheck disable=SC2034
{
	skill_name=pickup
	skill_src="$here/skills/pickup"
	skill_files='SKILL.md list-handoffs.sh'
	skill_hint='Start a new Claude Code session and run /pickup to resume from a handoff. The handoff skill writes the files this one reads.'
}

# shellcheck source=/dev/null
. "$lib"
install_skill "$@"
