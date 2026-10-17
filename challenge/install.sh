#!/bin/sh
# Install or remove the challenge skill for Claude Code without the plugin system.
#
# Copies the files in skills/challenge/ from this folder to
#   ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills/challenge/
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
	skill_name=challenge
	skill_src="$here/skills/challenge"
	skill_files='SKILL.md reference.md challenge-common.sh challenge-log.sh challenge-run.sh'
	skill_hint='Start a new Claude Code session and run /challenge. Each run starts two headless Claude sessions plus a differential step, so it spends plan quota or metered money.'
}

# shellcheck source=/dev/null
. "$lib"
install_skill "$@"
