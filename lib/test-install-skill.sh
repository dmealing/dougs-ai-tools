#!/bin/sh
# Tests shared by every tool's install.sh: source it, do not run it.
#
# The caller sets these and sources test-helpers.sh first:
#   installer    the install.sh under test
#   skill_name   the skill's folder name, for example handoff
#   skill_src    the directory that holds the shipped files
#   skill_files  the file names install.sh installs, separated by spaces
#
# Every case runs against a throwaway config directory, so nothing under the
# real Claude Code configuration is touched.

# shellcheck disable=SC2154

work=$(mktemp -d "${TMPDIR:-/tmp}/$skill_name-install-test.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT INT TERM

# run_installer <config dir> [args...]: sets $status and writes $work/out.
run_installer() {
	cfg=$1
	shift
	CLAUDE_CONFIG_DIR="$cfg" sh "$installer" "$@" >"$work/out" 2>&1
	status=$?
}
output_has() { grep -q -- "$1" "$work/out"; }

# all_installed <skill dir>: every shipped file is there and identical.
all_installed() {
	for shipped_file in $skill_files; do
		cmp -s "$skill_src/$shipped_file" "$1/$shipped_file" || return 1
	done
}
# none_installed <skill dir>: no shipped file is there.
none_installed() {
	for shipped_file in $skill_files; do
		[ ! -e "$1/$shipped_file" ] || return 1
	done
}
# all_reported <prefix> <skill dir>: the output names every file after the prefix.
all_reported() {
	for shipped_file in $skill_files; do
		output_has "$1: $2/$shipped_file" || return 1
	done
}

# The file the refusal cases modify: the last one, so a refusal has to be
# decided before the files ahead of it are touched; the first one is the one a
# refusal must leave in place.
last_file=${skill_files##* }
first_file=${skill_files%% *}

# --- install into an empty config directory --------------------------------
cfg="$work/fresh"
dest_dir="$cfg/skills/$skill_name"
dest="$dest_dir/$last_file"
run_installer "$cfg"
check "install exits 0" [ "$status" -eq 0 ]
check "install copies every shipped file" all_installed "$dest_dir"
check "install reports each destination" all_reported "Installed" "$dest_dir"

# --- re-install is idempotent ---------------------------------------------
run_installer "$cfg"
check "re-install exits 0" [ "$status" -eq 0 ]
check "re-install reports up to date" output_has "Already installed"
check "re-install leaves the files intact" all_installed "$dest_dir"

# --- refuses to overwrite a different file ---------------------------------
printf 'my own edits\n' >"$dest"
run_installer "$cfg"
check "install over a different file fails" [ "$status" -ne 0 ]
check "refusal names --force" output_has "--force"
check "refusal keeps the existing file" [ "$(cat "$dest")" = "my own edits" ]

# --- --force replaces it ----------------------------------------------------
run_installer "$cfg" --force
check "--force exits 0" [ "$status" -eq 0 ]
check "--force replaces the file" all_installed "$dest_dir"

# --- --uninstall refuses a modified copy, then removes with --force ---------
printf 'my own edits\n' >"$dest"
run_installer "$cfg" --uninstall
check "--uninstall of a modified copy fails" [ "$status" -ne 0 ]
check "--uninstall refusal removes nothing" [ -f "$dest_dir/$first_file" ]
check "--uninstall refusal keeps the modified file" [ "$(cat "$dest")" = "my own edits" ]
run_installer "$cfg" --uninstall --force
check "--uninstall --force exits 0" [ "$status" -eq 0 ]
check "--uninstall --force removes every file" none_installed "$dest_dir"

# --- --uninstall removes an unmodified install and its folder ---------------
run_installer "$cfg"
run_installer "$cfg" --uninstall
check "--uninstall exits 0" [ "$status" -eq 0 ]
check "--uninstall removes every file" none_installed "$dest_dir"
check "--uninstall reports each removal" all_reported "Removed" "$dest_dir"
check "--uninstall removes the empty folder" [ ! -d "$dest_dir" ]
check "--uninstall leaves the skills folder" [ -d "$cfg/skills" ]

# --- --uninstall keeps a folder that holds other files ----------------------
run_installer "$cfg"
printf 'keep me\n' >"$dest_dir/notes.txt"
run_installer "$cfg" --uninstall
check "--uninstall keeps unrelated files" [ -f "$dest_dir/notes.txt" ]
check "--uninstall still removes the skill beside them" none_installed "$dest_dir"

# --- --uninstall when nothing is installed ----------------------------------
run_installer "$work/never"
run_installer "$work/never" --uninstall
run_installer "$work/never" --uninstall
check "--uninstall twice exits 0" [ "$status" -eq 0 ]
check "--uninstall twice reports not installed" output_has "Not installed"

# --- falls back to HOME when CLAUDE_CONFIG_DIR is unset ---------------------
fake_home="$work/home dir"
mkdir -p "$fake_home"
(
	unset CLAUDE_CONFIG_DIR
	HOME="$fake_home" sh "$installer"
) >"$work/out" 2>&1
status=$?
check "HOME fallback exits 0" [ "$status" -eq 0 ]
check "HOME fallback installs under .claude (path with a space)" \
	all_installed "$fake_home/.claude/skills/$skill_name"

# --- rejects an unknown option ----------------------------------------------
run_installer "$cfg" --bogus
check "unknown option fails" [ "$status" -ne 0 ]
check "unknown option prints usage" output_has "Usage:"

run_installer "$cfg" --help
check "--help exits 0" [ "$status" -eq 0 ]
check "--help names the skill" output_has "$skill_name skill"
