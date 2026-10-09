#!/bin/sh
# Checks on the files the pickup sub-project ships:
#   1. none of them contains an absolute home-directory path;
#   2. the shell in the skill and in its script avoids constructs that stock
#      macOS lacks (bash 3.2, BSD userland);
#   3. the plugin manifest, the marketplace entry and the skill agree on names;
#   4. the script finds the store and the project by the handoff skill's rule.
#
# Run: sh pickup/tests/test-shipped-files.sh

# $store_rule and $project_rule come from the sourced shipped-file-checks.sh.
# shellcheck disable=SC2154

set -u

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)
root=$(dirname -- "$here")
repo=$(dirname -- "$root")
skill="$root/skills/pickup/SKILL.md"
script="$root/skills/pickup/list-handoffs.sh"

# shellcheck source=/dev/null
. "$repo/lib/test-helpers.sh"
# shellcheck source=/dev/null
. "$repo/lib/shipped-file-checks.sh"

# --- 1. no absolute home path ----------------------------------------------
check_no_home_path "$root" "$repo/lib" "$repo/tests" "$repo/README.md" "$repo/.claude-plugin"

check_claude_code_only "$root" "$repo/README.md" "$repo/.claude-plugin"

# --- 2. portable shell in the skill and its script --------------------------
check_portable_shell "$skill" "$script"
check "the script starts with a POSIX sh line" [ "$(sed -n '1p' "$script")" = "#!/bin/sh" ]

# --- 3. names line up --------------------------------------------------------
check_plugin_names pickup "$root" "$repo"

# --- 4. one rule for the store and the project ---------------------------------
# The script must contain the very lines the handoff skill documents, so the
# two cannot drift apart without this failing.
handoff_skill="$repo/handoff/skills/handoff/SKILL.md"
for rule in "$store_rule" "$project_rule"; do
	if rule_in_file "$rule" "$script" && rule_in_file "$rule" "$handoff_skill"; then
		pass "script and handoff skill share the rule: $(printf '%s\n' "$rule" | sed -n 1p)"
	else
		fail "script and handoff skill no longer share the rule: $(printf '%s\n' "$rule" | sed -n 1p)"
	fi
done

# --- the plugin declares its dependency, and the skill pre-approves only its own script
if python3 -c 'import json' >/dev/null 2>&1; then
	check "the plugin manifest depends on the handoff plugin" \
		[ "$(json_value "$root/.claude-plugin/plugin.json" dependencies)" = "['handoff']" ]
else
	printf 'skip - python3 not usable; plugin dependency not parsed\n'
fi
front_matter=$(awk 'NR == 1 && $0 == "---" { inside = 1; next } inside && $0 == "---" { exit } inside' "$skill")
# The ${...} is the literal text the skill carries, not a shell expansion.
# shellcheck disable=SC2016
allowed_rule='Bash(sh ${CLAUDE_SKILL_DIR}/list-handoffs.sh *)'
allows_script() { printf '%s\n' "$front_matter" | grep -qxF -- "  - $allowed_rule"; }
check "the skill allows its own listing script without a prompt" allows_script
rules_listed=$(printf '%s\n' "$front_matter" | grep -c '^  - ')
rules_for_script=$(printf '%s\n' "$front_matter" | grep '^  - ' | grep -cF 'list-handoffs.sh')
check "the skill pre-approves something" [ "$rules_listed" -ge 1 ]
check "every pre-approved command is that script" [ "$rules_listed" -eq "$rules_for_script" ]
no_blanket_rule() { ! printf '%s\n' "$front_matter" | grep -qE 'Bash\(((sh|bash)( \*|:\*)?|\*)\)'; }
check "the skill does not pre-approve a whole interpreter or tool" no_blanket_rule

# --- the skill runs the script that ships beside it -----------------------------
check "skill names the script it runs" grep -qF 'list-handoffs.sh' "$skill"
check "skill does not trigger on a bare continue" grep -qF 'bare "continue"' "$skill"

finish shipped-file
