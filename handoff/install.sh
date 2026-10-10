#!/bin/sh
# Install or remove the handoff skill for Claude Code without the plugin system.
#
# Copies skills/handoff/SKILL.md from this folder to
#   ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills/handoff/SKILL.md
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
	skill_name=handoff
	skill_src="$here/skills/handoff"
	skill_files='SKILL.md reference.md'
	skill_hint='Start a new Claude Code session and run /handoff when you want to hand work off.'
}

# shellcheck source=/dev/null
. "$lib"
install_skill "$@"
