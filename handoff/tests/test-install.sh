#!/bin/sh
# Tests for ../install.sh. Every case runs against a throwaway config directory,
# so nothing under the real Claude Code configuration is touched.
#
# Run: sh handoff/tests/test-install.sh

set -u

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)
root=$(dirname -- "$here")
installer="$root/install.sh"
shipped="$root/skills/handoff/SKILL.md"

work=$(mktemp -d "${TMPDIR:-/tmp}/handoff-install-test.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT INT TERM

failures=0
pass() { printf 'ok   - %s\n' "$1"; }
fail() {
	printf 'FAIL - %s\n' "$1"
	failures=$((failures + 1))
}
check() {
	# check <description> <command...>: passes when the command succeeds.
	desc=$1
	shift
	if "$@"; then pass "$desc"; else fail "$desc"; fi
}

# run_installer <config dir> [args...]: sets $status and writes $work/out.
run_installer() {
	cfg=$1
	shift
	CLAUDE_CONFIG_DIR="$cfg" sh "$installer" "$@" >"$work/out" 2>&1
	status=$?
}
output_has() { grep -q -- "$1" "$work/out"; }

# --- install into an empty config directory --------------------------------
cfg="$work/fresh"
dest="$cfg/skills/handoff/SKILL.md"
run_installer "$cfg"
check "install exits 0" [ "$status" -eq 0 ]
check "install copies the skill" cmp -s "$shipped" "$dest"
check "install reports the destination" output_has "Installed: $dest"

# --- re-install is idempotent ---------------------------------------------
run_installer "$cfg"
check "re-install exits 0" [ "$status" -eq 0 ]
check "re-install reports up to date" output_has "Already installed"
check "re-install leaves the skill intact" cmp -s "$shipped" "$dest"

# --- refuses to overwrite a different file ---------------------------------
printf 'my own edits\n' >"$dest"
run_installer "$cfg"
check "install over a different file fails" [ "$status" -ne 0 ]
check "refusal names --force" output_has "--force"
check "refusal keeps the existing file" [ "$(cat "$dest")" = "my own edits" ]

# --- --force replaces it ----------------------------------------------------
run_installer "$cfg" --force
check "--force exits 0" [ "$status" -eq 0 ]
check "--force replaces the file" cmp -s "$shipped" "$dest"

# --- --uninstall refuses a modified copy, then removes with --force ---------
printf 'my own edits\n' >"$dest"
run_installer "$cfg" --uninstall
check "--uninstall of a modified copy fails" [ "$status" -ne 0 ]
check "--uninstall refusal keeps the file" [ -f "$dest" ]
run_installer "$cfg" --uninstall --force
check "--uninstall --force exits 0" [ "$status" -eq 0 ]
check "--uninstall --force removes the file" [ ! -e "$dest" ]

# --- --uninstall removes an unmodified install and its folder ---------------
run_installer "$cfg"
run_installer "$cfg" --uninstall
check "--uninstall exits 0" [ "$status" -eq 0 ]
check "--uninstall removes the skill" [ ! -e "$dest" ]
check "--uninstall removes the empty folder" [ ! -d "$cfg/skills/handoff" ]
check "--uninstall leaves the skills folder" [ -d "$cfg/skills" ]

# --- --uninstall keeps a folder that holds other files ----------------------
run_installer "$cfg"
printf 'keep me\n' >"$cfg/skills/handoff/notes.txt"
run_installer "$cfg" --uninstall
check "--uninstall keeps unrelated files" [ -f "$cfg/skills/handoff/notes.txt" ]
check "--uninstall still removes the skill beside them" [ ! -e "$dest" ]

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
	cmp -s "$shipped" "$fake_home/.claude/skills/handoff/SKILL.md"

# --- rejects an unknown option ----------------------------------------------
run_installer "$cfg" --bogus
check "unknown option fails" [ "$status" -ne 0 ]
check "unknown option prints usage" output_has "Usage:"

run_installer "$cfg" --help
check "--help exits 0" [ "$status" -eq 0 ]

if [ "$failures" -ne 0 ]; then
	printf '%s check(s) failed\n' "$failures"
	exit 1
fi
printf 'all install checks passed\n'
