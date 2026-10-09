#!/bin/sh
# Install or remove the handoff skill for Claude Code without the plugin system.
#
# Copies skills/handoff/SKILL.md from this folder to
#   ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills/handoff/SKILL.md
#
# POSIX sh; runs on macOS and Linux.

set -eu

usage() {
	cat <<'EOF'
Usage: install.sh [--force] [--uninstall] [--help]

Installs the handoff skill into ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills/handoff/.

  --force      Replace (or, with --uninstall, remove) an installed copy that
               differs from the one shipped here.
  --uninstall  Remove the installed skill.
  --help       Show this text.
EOF
}

die() {
	printf 'install.sh: %s\n' "$1" >&2
	exit 1
}

force=0
uninstall=0
for arg in "$@"; do
	case "$arg" in
	--force) force=1 ;;
	--uninstall) uninstall=1 ;;
	-h | --help)
		usage
		exit 0
		;;
	*)
		usage >&2
		die "unknown option: $arg"
		;;
	esac
done

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)
src="$here/skills/handoff/SKILL.md"

if [ -n "${CLAUDE_CONFIG_DIR:-}" ]; then
	config_dir=$CLAUDE_CONFIG_DIR
elif [ -n "${HOME:-}" ]; then
	config_dir=$HOME/.claude
else
	die "neither CLAUDE_CONFIG_DIR nor HOME is set"
fi
dest_dir="$config_dir/skills/handoff"
dest="$dest_dir/SKILL.md"

[ -f "$src" ] || die "cannot find the skill to install: $src"

if [ "$uninstall" -eq 1 ]; then
	if [ ! -e "$dest" ]; then
		printf 'Not installed: %s\n' "$dest"
		exit 0
	fi
	if [ "$force" -eq 0 ] && ! cmp -s "$src" "$dest"; then
		die "$dest differs from the shipped skill; not removing it. Re-run with --uninstall --force to remove it anyway."
	fi
	rm -f "$dest"
	# Leave the folder in place if the user keeps other files in it.
	rmdir "$dest_dir" 2>/dev/null || true
	printf 'Removed: %s\n' "$dest"
	exit 0
fi

if [ -e "$dest" ]; then
	if cmp -s "$src" "$dest"; then
		printf 'Already installed and up to date: %s\n' "$dest"
		exit 0
	fi
	if [ "$force" -eq 0 ]; then
		die "$dest already exists and differs from the shipped skill; not overwriting it. Re-run with --force to replace it."
	fi
fi

mkdir -p "$dest_dir"
cp "$src" "$dest"
printf 'Installed: %s\n' "$dest"
printf 'Start a new Claude Code session and run /handoff when you want to hand work off.\n'
