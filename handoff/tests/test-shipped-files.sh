#!/bin/sh
# Checks on the files this repository ships:
#   1. none of them contains an absolute home-directory path;
#   2. the shell in the skill avoids constructs that stock macOS lacks
#      (bash 3.2, BSD userland);
#   3. the plugin manifest, the marketplace entry and the skill agree on names.
#
# Run: sh handoff/tests/test-shipped-files.sh

set -u

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)
root=$(dirname -- "$here")
repo=$(dirname -- "$root")
skill="$root/skills/handoff/SKILL.md"

# shellcheck source=/dev/null
. "$here/helpers.sh"

# --- 1. no absolute home path ----------------------------------------------
# A user directory under the Linux, macOS or Windows home root.
home_pattern='(/(home|Users)/|[A-Za-z]:\\Users\\)[A-Za-z0-9._-]+'
hits=$(grep -rnE --exclude-dir=.git -- "$home_pattern" \
	"$root" "$repo/README.md" "$repo/.claude-plugin" 2>/dev/null)
if [ -z "$hits" ]; then
	pass "no absolute home path in shipped files"
else
	fail "absolute home path in shipped files:"
	printf '%s\n' "$hits"
fi

# --- 2. portable shell in the skill ----------------------------------------
for construct in 'mapfile' 'readarray' 'declare -A' '-printf' 'date -d' 'date --date' \
	'readlink -f' 'realpath' 'sed -i' 'grep -P'; do
	if grep -nF -- "$construct" "$skill" >/dev/null; then
		fail "skill uses a construct stock macOS lacks: $construct"
	else
		pass "skill avoids: $construct"
	fi
done
if grep -nE '(^|[^[:alnum:]_-])tac([^[:alnum:]_-]|$)' "$skill" >/dev/null; then
	fail "skill uses a construct stock macOS lacks: tac"
else
	pass "skill avoids: tac"
fi

# --- 3. names line up --------------------------------------------------------
manifest="$root/.claude-plugin/plugin.json"
marketplace="$repo/.claude-plugin/marketplace.json"
name_line='"name"[[:space:]]*:[[:space:]]*"handoff"'
if grep -qE -- "$name_line" "$manifest"; then
	pass "plugin manifest is named handoff"
else
	fail "plugin manifest is not named handoff"
fi
if grep -qE -- "$name_line" "$marketplace"; then
	pass "marketplace lists a plugin named handoff"
else
	fail "marketplace does not list a plugin named handoff"
fi
if grep -qE -- '"source"[[:space:]]*:[[:space:]]*"\./handoff"' "$marketplace"; then
	pass "marketplace entry points at ./handoff"
else
	fail "marketplace entry does not point at ./handoff"
fi
if [ "$(sed -n '1p' "$skill")" = "---" ] && grep -qx 'name: handoff' "$skill"; then
	pass "skill front matter names the skill handoff"
else
	fail "skill front matter does not name the skill handoff"
fi

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
	if grep -qF "sed -n '1s/^worktree //p'" "$skill"; then
		pass "skill documents the same rule this test runs"
	else
		fail "skill no longer contains the project-name rule this test runs"
	fi
else
	printf 'skip - git not found; project-name rule not exercised\n'
fi

# --- the store-root rule in the skill, run for real ---------------------------
# Same approach: restate the documented line and check all three cases.
# The single quotes are deliberate: the literal text is evaluated below.
# shellcheck disable=SC2016
root_rule='root="${HANDOFF_DIR:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/handoffs}"'
store_root() (
	eval "$root_rule"
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
if grep -qF -- "$root_rule" "$skill"; then
	pass "skill documents the same store rule this test runs"
else
	fail "skill no longer contains the store rule this test runs"
fi

finish shipped-file
