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

check_claude_code_only "$root" "$repo/README.md" "$repo/.claude-plugin"

# --- 2. portable shell in the skill ----------------------------------------
check_portable_shell "$skill"

# --- 3. names line up --------------------------------------------------------
check_plugin_names handoff "$root" "$repo"

# --- the project-name rule in the skill, run for real ------------------------
# The rule's own lines are run in scratch repositories: an ordinary one with a
# second worktree, and bare clones with working trees beside them. The skill
# must contain exactly those lines, so a change to the rule has to change this.
if command -v git >/dev/null 2>&1; then
	work=$(mktemp -d "${TMPDIR:-/tmp}/handoff-project-test.XXXXXX") || exit 1
	trap 'rm -rf "$work"' EXIT INT TERM
	resolve() {
		eval "$project_rule"
		printf '%s\n' "$project"
	}
	expect_project() {
		# expect_project <description> <expected> <directory>
		actual=$(cd "$3" && GIT_CEILING_DIRECTORIES="$work" resolve)
		if [ "$actual" = "$2" ]; then pass "$1"; else fail "$1: got '$actual'"; fi
	}
	mkdir -p "$work/widget shop" "$work/plain-folder"
	(
		cd "$work/widget shop" &&
			git init -q . &&
			git -c user.name=test -c user.email=test@example.invalid \
				commit -q --allow-empty -m init &&
			git worktree add -q "$work/side-branch" -b side >/dev/null 2>&1
	)
	expect_project "project name in the main working tree" "widget shop" "$work/widget shop"
	expect_project "a second worktree shares the project name" "widget shop" "$work/side-branch"
	expect_project "outside a repository the folder name is used" "plain-folder" "$work/plain-folder"
	# A bare clone with working trees beside it: the bare directory names nothing.
	bare_layout() {
		# bare_layout <folder> <bare directory name>
		mkdir -p "$work/$1"
		git clone -q --bare "$work/widget shop" "$work/$1/$2" >/dev/null 2>&1
		(cd "$work/$1/$2" && git worktree add -q ../main side) >/dev/null 2>&1
	}
	bare_layout stone-mill .bare
	bare_layout grain-store .git
	bare_layout salt-works salt-works.git
	bare_layout tide-table tide-table-bare
	expect_project "a .bare directory takes its parent's name" stone-mill "$work/stone-mill/main"
	expect_project "a .git bare directory takes its parent's name" grain-store "$work/grain-store/main"
	expect_project "name.git becomes name" salt-works "$work/salt-works/main"
	expect_project "any other bare directory keeps its name" tide-table-bare "$work/tide-table/main"
	expect_project "the same from inside the bare directory" stone-mill "$work/stone-mill/.bare"
	expect_project "name.git becomes name from inside it" salt-works "$work/salt-works/salt-works.git"
	# Only a bare first entry is renamed.
	mkdir -p "$work/odd.git"
	(cd "$work/odd.git" && git init -q .) >/dev/null 2>&1
	expect_project "a working tree folder that ends in .git keeps its name" "odd.git" "$work/odd.git"
	if rule_in_file "$project_rule" "$skill"; then
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

# --- the header, the secrets line and the one place that says when to write ------
check "the header template carries the commit line" grep -qF '**Commit:** `<short hash' "$skill"
check "the skill tells the agent to leave out secrets" grep -qF '**Leave out secrets:**' "$skill"
front_matter=$(awk 'NR == 1 && $0 == "---" { inside = 1; next } inside && $0 == "---" { exit } inside' "$skill")
no_model_invocation_switch() { ! printf '%s\n' "$front_matter" | grep -q 'disable-model-invocation'; }
check "the skill is not hidden from plain-words requests" no_model_invocation_switch
rule_above_gate() {
	rule_line=$(grep -n '^\*\*A handoff is written only when the user asks for one' "$skill" | cut -d: -f1)
	gate_line=$(grep -n '^# PART 1' "$skill" | cut -d: -f1)
	[ -n "$rule_line" ] && [ -n "$gate_line" ] && [ "$rule_line" -lt "$gate_line" ]
}
check "the rule on when to write sits above the first gate" rule_above_gate
rule_stated_once() { [ "$(grep -c 'only when the user asks' "$skill")" -eq 1 ]; }
check "the rule on when to write is stated once" rule_stated_once

# --- the skill stays short; the long parts load on demand ---------------------------
reference="$root/skills/handoff/reference.md"
skill_lines=$(wc -l <"$skill" | tr -d ' ')
check "the skill stays under 240 lines ($skill_lines now)" [ "$skill_lines" -le 240 ]
check "the on-demand reference ships" [ -f "$reference" ]
check "the skill points at the on-demand reference" grep -qF 'reference.md' "$skill"
check "the reference holds the worked example" grep -q '^# Worked example' "$reference"
check "the reference holds the mistakes list" grep -q '^# Common mistakes' "$reference"
# shellcheck disable=SC2016
check "the skill no longer carries the worked example" sh -c '! grep -q "^## Worked example" "$1"' _ "$skill"
gates_first() {
	gate_line=$(grep -n '^# PART 1' "$skill" | cut -d: -f1)
	example_ref=$(grep -n 'reference.md' "$skill" | head -n 1 | cut -d: -f1)
	[ -n "$gate_line" ] && [ -n "$example_ref" ] && [ "$gate_line" -gt 0 ] && grep -q '^## Gate 3' "$skill"
}
check "all three gates stay in the skill" gates_first

# --- what the next session is for, and keeping the previous version -------------------
check "the skill accepts words after /handoff as the next session's purpose" grep -qF '**Next session:**' "$skill"
check "the skill keeps dead ends whatever the purpose" grep -qF 'do not** drop a dead end' "$skill"
# shellcheck disable=SC2016
check "the skill copies the previous version to done/ before a rewrite" \
	grep -qF 'cp -p "$dir/<stream>.md" "$dir/done/<stream>-$(date +%Y%m%d-%H%M%S).md"' "$skill"

# --- credit for the work this one drew on ---------------------------------------
upstream='ostikwhy-blip/claude-code-handoff-skill'
check "the root NOTICE carries the upstream copyright line" grep -qxF 'Copyright (c) 2026 ostikwhy-blip' "$repo/NOTICE"
check "the root NOTICE carries the upstream permission notice" \
	grep -qF 'Permission is hereby granted, free of charge, to any person obtaining a copy' "$repo/NOTICE"
check "the handoff README credits the upstream project" grep -qF "$upstream" "$root/README.md"
check "the root README mentions the NOTICE file" grep -qF 'NOTICE' "$repo/README.md"

finish shipped-file
