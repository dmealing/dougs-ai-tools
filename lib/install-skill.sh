#!/bin/sh
# Shared by each tool's install.sh: source it, do not run it.
#
# Installs or removes one skill for Claude Code without the plugin system, by
# copying files from <tool>/skills/<name>/ to
#   ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills/<name>/
#
# The caller sets these, sources this file, then calls install_skill "$@":
#   skill_name   the skill's folder name under skills/, for example handoff
#   skill_src    the directory that holds the files to install
#   skill_files  the file names to install from it, separated by spaces
#   skill_hint   one line printed after a successful install
#
# POSIX sh; runs on macOS and Linux.

# The four variables above come from the caller.
# shellcheck disable=SC2154

install_skill_usage() {
	cat <<EOF
Usage: install.sh [--force] [--uninstall] [--help]

Installs the $skill_name skill into \${CLAUDE_CONFIG_DIR:-\$HOME/.claude}/skills/$skill_name/.

  --force      Replace (or, with --uninstall, remove) an installed copy that
               differs from the one shipped here.
  --uninstall  Remove the installed skill.
  --help       Show this text.
EOF
}

install_skill_die() {
	printf 'install.sh: %s\n' "$1" >&2
	exit 1
}

install_skill() {
	force=0
	uninstall=0
	for arg in "$@"; do
		case "$arg" in
		--force) force=1 ;;
		--uninstall) uninstall=1 ;;
		-h | --help)
			install_skill_usage
			exit 0
			;;
		*)
			install_skill_usage >&2
			install_skill_die "unknown option: $arg"
			;;
		esac
	done

	if [ -n "${CLAUDE_CONFIG_DIR:-}" ]; then
		config_dir=$CLAUDE_CONFIG_DIR
	elif [ -n "${HOME:-}" ]; then
		config_dir=$HOME/.claude
	else
		install_skill_die "neither CLAUDE_CONFIG_DIR nor HOME is set"
	fi
	dest_dir="$config_dir/skills/$skill_name"

	for file in $skill_files; do
		[ -f "$skill_src/$file" ] || install_skill_die "cannot find the file to install: $skill_src/$file"
	done

	# Every refusal is decided before anything is copied or removed, so a
	# refused run leaves the installed skill exactly as it was.
	if [ "$uninstall" -eq 1 ]; then
		for file in $skill_files; do
			dest="$dest_dir/$file"
			if [ -e "$dest" ] && [ "$force" -eq 0 ] && ! cmp -s "$skill_src/$file" "$dest"; then
				install_skill_die "$dest differs from the shipped copy; not removing it. Re-run with --uninstall --force to remove it anyway."
			fi
		done
		for file in $skill_files; do
			dest="$dest_dir/$file"
			if [ -e "$dest" ]; then
				rm -f "$dest"
				printf 'Removed: %s\n' "$dest"
			else
				printf 'Not installed: %s\n' "$dest"
			fi
		done
		# Leave the folder in place if the user keeps other files in it.
		rmdir "$dest_dir" 2>/dev/null || true
		exit 0
	fi

	for file in $skill_files; do
		dest="$dest_dir/$file"
		if [ -e "$dest" ] && [ "$force" -eq 0 ] && ! cmp -s "$skill_src/$file" "$dest"; then
			install_skill_die "$dest already exists and differs from the shipped copy; not overwriting it. Re-run with --force to replace it."
		fi
	done

	mkdir -p "$dest_dir"
	copied=0
	for file in $skill_files; do
		dest="$dest_dir/$file"
		if [ -e "$dest" ] && cmp -s "$skill_src/$file" "$dest"; then
			printf 'Already installed and up to date: %s\n' "$dest"
		else
			cp "$skill_src/$file" "$dest"
			printf 'Installed: %s\n' "$dest"
			copied=1
		fi
	done
	if [ "$copied" -eq 1 ]; then
		printf '%s\n' "$skill_hint"
	fi
}
