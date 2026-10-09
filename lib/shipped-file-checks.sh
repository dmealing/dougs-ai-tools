#!/bin/sh
# Checks every tool runs on the files it ships: source it, do not run it.
# Source test-helpers.sh first; these functions report through pass and fail.

# check_no_home_path <path>...: none of the files contains an absolute path
# into a user's home directory under the Linux, macOS or Windows home root.
check_no_home_path() {
	home_pattern='(/(home|Users)/|[A-Za-z]:\\Users\\)[A-Za-z0-9._-]+'
	hits=$(grep -rnE --exclude-dir=.git -- "$home_pattern" "$@" 2>/dev/null)
	if [ -z "$hits" ]; then
		pass "no absolute home path in shipped files"
	else
		fail "absolute home path in shipped files:"
		printf '%s\n' "$hits"
	fi
}

# check_claude_code_only <path>...: nothing claims the tools suit other agents.
check_claude_code_only() {
	hits=$(grep -rniE --exclude-dir=.git -- 'similar coding agents|other coding agents' "$@" 2>/dev/null)
	if [ -z "$hits" ]; then
		pass "the shipped text describes the tools as being for Claude Code"
	else
		fail "the shipped text mentions other coding agents:"
		printf '%s\n' "$hits"
	fi
}

# check_portable_shell <file>...: the shell in each file avoids constructs
# that stock macOS lacks (bash 3.2, BSD userland).
check_portable_shell() {
	for checked_file in "$@"; do
		checked_name=$(basename -- "$checked_file")
		for construct in 'mapfile' 'readarray' 'declare -A' '-printf' 'date -d' 'date --date' \
			'readlink -f' 'realpath' 'sed -i' 'grep -P'; do
			if grep -nF -- "$construct" "$checked_file" >/dev/null; then
				fail "$checked_name uses a construct stock macOS lacks: $construct"
			else
				pass "$checked_name avoids: $construct"
			fi
		done
		if grep -nE '(^|[^[:alnum:]_-])tac([^[:alnum:]_-]|$)' "$checked_file" >/dev/null; then
			fail "$checked_name uses a construct stock macOS lacks: tac"
		else
			pass "$checked_name avoids: tac"
		fi
	done
}

# check_plugin_names <tool> <tool folder> <repository folder>: the plugin
# manifest, the marketplace entry and the skill agree on the tool's name.
check_plugin_names() {
	tool=$1
	manifest="$2/.claude-plugin/plugin.json"
	marketplace="$3/.claude-plugin/marketplace.json"
	tool_skill="$2/skills/$tool/SKILL.md"
	if python3 -c 'import json' >/dev/null 2>&1; then
		if [ "$(json_value "$manifest" name)" = "$tool" ]; then
			pass "plugin manifest is named $tool"
		else
			fail "plugin manifest is not named $tool, or is not valid JSON"
		fi
		if [ "$(json_value "$marketplace" plugins "$tool" source)" = "./$tool" ]; then
			pass "marketplace lists a plugin named $tool at ./$tool"
		else
			fail "marketplace does not list a plugin named $tool at ./$tool, or is not valid JSON"
		fi
	else
		printf 'skip - python3 not usable; plugin and marketplace JSON not parsed\n'
	fi
	if [ "$(sed -n '1p' "$tool_skill")" = "---" ] && grep -qx "name: $tool" "$tool_skill"; then
		pass "skill front matter names the skill $tool"
	else
		fail "skill front matter does not name the skill $tool"
	fi
}

# json_value <file> <key> [<key>...]: print the value at that path. A list is
# stepped into by the "name" of one of its elements.
json_value() {
	python3 - "$@" 2>/dev/null <<'EOF'
import json, sys
try:
    doc = json.load(open(sys.argv[1]))
    for key in sys.argv[2:]:
        if isinstance(doc, list):
            doc = [item for item in doc if item.get("name") == key][0]
        else:
            doc = doc[key]
    print(doc)
except Exception:
    sys.exit(1)
EOF
}

# The store rule and the project rule, exactly as the handoff skill documents
# them. Anything that reads the store has to contain the same text, and the
# tests run these very lines. The project rule is several lines long.
# The single quotes are deliberate: the literal text is evaluated or searched
# for. Both variables are read by the scripts that source this file.
# shellcheck disable=SC2016,SC2034
store_rule='root="${HANDOFF_DIR:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/handoffs}"'
# shellcheck disable=SC2034
project_rule=$(
	cat <<'EOF'
main=$(git worktree list --porcelain 2>/dev/null | sed -n '1s/^worktree //p')
bare=$(git worktree list --porcelain 2>/dev/null | sed -n '2s/^bare$/yes/p')
project=$(basename "${main:-$PWD}")
if [ -n "$bare" ]; then case "$project" in .bare | .git) project=$(basename "$(dirname "$main")") ;; *.git) project=${project%.git} ;; esac; fi
EOF
)

# rule_in_file <rule> <file>: every line of the rule is, whole, a line of the file.
rule_in_file() {
	printf '%s\n' "$1" | while IFS= read -r rule_line; do
		grep -qxF -- "$rule_line" "$2" || exit 1
	done
}
