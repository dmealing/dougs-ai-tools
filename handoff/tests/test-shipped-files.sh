#!/bin/sh
# Checks on the files this repository ships:
#   1. none of them contains an absolute home-directory path;
#   2. the shell in the skill avoids constructs that stock macOS lacks
#      (bash 3.2, BSD userland);
#   3. the plugin manifest, the marketplace entry and the skill agree on names.
#
# Run: sh handoff/tests/test-shipped-files.sh

# $store_rule and $project_rule come from the sourced shipped-file-checks.sh.
# shellcheck disable=SC2154

set -u

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)
root=$(dirname -- "$here")
repo=$(dirname -- "$root")
skill="$root/skills/handoff/SKILL.md"

# shellcheck source=/dev/null
. "$repo/lib/test-helpers.sh"
# shellcheck source=/dev/null
. "$repo/lib/shipped-file-checks.sh"

# --- 1. no absolute home path ----------------------------------------------
check_no_home_path "$root" "$repo/lib" "$repo/tests" "$repo/README.md" "$repo/.claude-plugin"

# --- 2. portable shell in the skill ----------------------------------------
check_portable_shell "$skill"

# --- 3. names line up --------------------------------------------------------
check_plugin_names handoff "$root" "$repo"

# --- the project-name rule in the skill, run for real ------------------------
# Extract nothing: restate the documented rule and check it in a scratch repo
# with a second worktree, so a change to the rule has to change this too.
if command -v git >/dev/null 2>&1; then
	work=$(mktemp -d "${TMPDIR:-/tmp}/handoff-project-test.XXXXXX") || exit 1
	trap 'rm -rf "$work"' EXIT INT TERM
	resolve() {
		main=$(git worktree list --porcelain 2>/dev/null | sed -n '1s/^worktree //p')
		basename "${main:-$PWD}"
	}
	mkdir -p "$work/widget shop" "$work/plain-folder"
	(
		cd "$work/widget shop" &&
			git init -q . &&
			git -c user.name=test -c user.email=test@example.invalid \
				commit -q --allow-empty -m init &&
			git worktree add -q "$work/side-branch" -b side >/dev/null 2>&1
	)
	from_main=$(cd "$work/widget shop" && resolve)
	from_side=$(cd "$work/side-branch" && resolve)
	from_plain=$(cd "$work/plain-folder" && GIT_CEILING_DIRECTORIES="$work" resolve)
	if [ "$from_main" = "widget shop" ]; then
		pass "project name in the main working tree"
	else
		fail "project name in the main working tree: got '$from_main'"
	fi
	if [ "$from_side" = "widget shop" ]; then
		pass "a second worktree shares the project name"
	else
		fail "a second worktree shares the project name: got '$from_side'"
	fi
	if [ "$from_plain" = "plain-folder" ]; then
		pass "outside a repository the folder name is used"
	else
		fail "outside a repository the folder name is used: got '$from_plain'"
	fi
	if grep -qF -- "$project_rule" "$skill"; then
		pass "skill documents the same rule this test runs"
	else
		fail "skill no longer contains the project-name rule this test runs"
	fi
else
	printf 'skip - git not found; project-name rule not exercised\n'
fi

# --- the store-root rule in the skill, run for real ---------------------------
# Same approach: restate the documented line and check all three cases.
store_root() (
	eval "$store_rule"
	printf '%s\n' "$root"
)
expect_root() {
	# expect_root <description> <expected> <actual>
	if [ "$2" = "$3" ]; then pass "$1"; else fail "$1: got '$3'"; fi
}
expect_root "default store is the handoffs folder under the home .claude" \
	"/scratch/user/.claude/handoffs" \
	"$(unset HANDOFF_DIR CLAUDE_CONFIG_DIR; HOME=/scratch/user store_root)"
expect_root "CLAUDE_CONFIG_DIR moves the default store" \
	"/scratch/config/handoffs" \
	"$(unset HANDOFF_DIR; CLAUDE_CONFIG_DIR=/scratch/config HOME=/scratch/user store_root)"
expect_root "HANDOFF_DIR overrides the store" \
	"/tmp" \
	"$(HANDOFF_DIR=/tmp CLAUDE_CONFIG_DIR=/scratch/config HOME=/scratch/user store_root)"
if grep -qF -- "$store_rule" "$skill"; then
	pass "skill documents the same store rule this test runs"
else
	fail "skill no longer contains the store rule this test runs"
fi

finish shipped-file
