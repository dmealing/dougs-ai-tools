#!/bin/sh
# Checks on the files the challenge sub-project ships:
#   1. none of them contains an absolute home-directory path or a tilde path;
#   2. the shell avoids constructs that stock macOS lacks, and constructs POSIX
#      sh lacks;
#   3. the plugin manifest, the marketplace entry and the skill agree on names;
#   4. the skill pre-approves only its own scripts;
#   5. the public documents carry the warnings and labels they must.
#
# Run: sh challenge/tests/test-shipped-files.sh

# The single quotes hold code that holds() evaluates.
# shellcheck disable=SC2016,SC2034

set -u

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)
root=$(dirname -- "$here")
repo=$(dirname -- "$root")
skill_dir="$root/skills/challenge"
skill="$skill_dir/SKILL.md"
scripts="$skill_dir/challenge-common.sh $skill_dir/challenge-log.sh $skill_dir/challenge-run.sh"

# shellcheck source=/dev/null
. "$repo/lib/test-helpers.sh"
# shellcheck source=/dev/null
. "$repo/lib/shipped-file-checks.sh"

# holds <shell code>: succeeds when the code does. For checks that combine tests.
holds() { eval "$1"; }

# --- 1. no absolute or tilde path -----------------------------------------------------
check_no_home_path "$root" "$repo/lib" "$repo/tests" "$repo/README.md" "$repo/.claude-plugin"
check_claude_code_only "$root" "$repo/README.md" "$repo/.claude-plugin"
tilde_hits=$(grep -rnE -- '(^|[^[:alnum:]])~/' "$skill_dir" "$root/README.md" "$root/install.sh" "$root/.claude-plugin" 2>/dev/null)
if [ -z "$tilde_hits" ]; then
	pass "no tilde path in shipped files"
else
	fail "tilde path in shipped files:"
	printf '%s\n' "$tilde_hits"
fi
backups=$(find "$root" -name '*.bak*' -o -name '*.orig' -o -name '*~' 2>/dev/null)
check "no backup or scratch file is shipped" [ -z "$backups" ]

# --- 2. portable shell ----------------------------------------------------------------------
# shellcheck disable=SC2086
check_portable_shell "$skill" $scripts "$root/install.sh"
# shellcheck disable=SC2086
check_posix_shell $scripts "$root/install.sh" "$here/stub-claude.sh"
for script in "$skill_dir/challenge-log.sh" "$skill_dir/challenge-run.sh" "$root/install.sh"; do
	check "$(basename -- "$script") is executable" [ -x "$script" ]
done

# --- 3. names line up -----------------------------------------------------------------------------
check_plugin_names challenge "$root" "$repo"

# --- 4. the skill pre-approves its own scripts and nothing else -----------------------------------
front_matter=$(awk 'NR == 1 && $0 == "---" { inside = 1; next } inside && $0 == "---" { exit } inside' "$skill")
if printf '%s\n' "$front_matter" | grep -qx 'disable-model-invocation: true'; then
	pass "the skill cannot start on its own"
else
	fail "the skill can start on its own"
fi
# The ${...} is the literal text the skill carries, not a shell expansion.
# shellcheck disable=SC2016,SC2034
for rule in 'Bash(sh ${CLAUDE_SKILL_DIR}/challenge-log.sh *)' 'Bash(sh "${CLAUDE_SKILL_DIR}/challenge-log.sh" *)' 'Bash(sh ${CLAUDE_SKILL_DIR}/challenge-run.sh *)' 'Bash(sh "${CLAUDE_SKILL_DIR}/challenge-run.sh" *)'; do
	if printf '%s\n' "$front_matter" | grep -qxF -- "  - $rule"; then
		pass "the skill allows: $rule"
	else
		fail "the skill does not allow: $rule"
	fi
done
rules_listed=$(printf '%s\n' "$front_matter" | grep -c '^  - ')
rules_for_scripts=$(printf '%s\n' "$front_matter" | grep '^  - ' | grep -cE 'challenge-(log|run)\.sh')
check "every pre-approved command is one of the two scripts" holds '[ "$rules_listed" -ge 1 ] && [ "$rules_listed" -eq "$rules_for_scripts" ]'
if printf '%s\n' "$front_matter" | grep -qE 'Bash\(((sh|bash|claude)( \*|:\*)?|\*)\)'; then
	fail "the skill pre-approves a whole interpreter or tool"
else
	pass "the skill does not pre-approve a whole interpreter or tool"
fi
check "the skill is under 250 lines" [ "$(wc -l <"$skill" | tr -d ' ')" -lt 250 ]

# --- 5. the warnings and labels -----------------------------------------------------------------------
check "the README labels the tool experimental" grep -qi 'experimental' "$root/README.md"
check "the README warns about Fable usage credits" grep -q 'usage credits' "$root/README.md"
check "the README notes the other challenge tool" grep -q 'PAL' "$root/README.md"
check "the README says arms are Claude-only" grep -qi 'claude-only\|only claude' "$root/README.md"
check "the manifest description says experimental" grep -qi '"description": "Experimental' "$root/.claude-plugin/plugin.json"
check "the marketplace entry says experimental and names the cost" python3 -c 'import json,sys; e=[p for p in json.load(open(sys.argv[1]))["plugins"] if p["name"]=="challenge"][0]["description"].lower(); sys.exit(0 if "experimental" in e and "quota" in e else 1)' "$repo/.claude-plugin/marketplace.json"
check "reference.md exists and is dated" grep -qE '20[0-9]{2}-[0-9]{2}-[0-9]{2}' "$skill_dir/reference.md"
session_hits=$(grep -nE 'session|slug|[0-9a-f]{12,}' "$skill_dir/reference.md" | grep -vi 'session identifier' | head -n 3)
check "reference.md names no session, slug or hash" [ -z "$session_hits" ]

finish shipped-file
