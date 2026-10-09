#!/bin/sh
# Checks on the files the context-nudge sub-project ships:
#   1. none of them contains an absolute home-directory path;
#   2. the scripts avoid constructs that stock macOS lacks (bash 3.2, BSD
#      userland) and start with a POSIX sh line;
#   3. the plugin manifest and the marketplace entry agree on names;
#   4. the plugin registers the hook, and names a script that ships;
#   5. the README documents every setting the scripts read.
#
# Run: sh context-nudge/tests/test-shipped-files.sh

set -u

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)
root=$(dirname -- "$here")
repo=$(dirname -- "$root")
readme="$root/README.md"

# shellcheck source=/dev/null
. "$repo/lib/test-helpers.sh"
# shellcheck source=/dev/null
. "$repo/lib/shipped-file-checks.sh"

# --- 1. no absolute home path ----------------------------------------------
check_no_home_path "$root" "$repo/lib" "$repo/tests" "$repo/README.md" "$repo/.claude-plugin"

# --- 2. portable shell --------------------------------------------------------
check_portable_shell "$root"/scripts/*.sh "$root/install.sh"
for script in "$root"/scripts/*.sh "$root/install.sh"; do
	name=$(basename -- "$script")
	check "$name starts with a POSIX sh line" [ "$(sed -n '1p' "$script")" = "#!/bin/sh" ]
	for construct in '-maxdepth' '[[' 'local ' 'echo -e' 'function '; do
		if grep -nF -- "$construct" "$script" >/dev/null; then
			fail "$name uses a construct POSIX sh lacks: $construct"
		else
			pass "$name avoids: $construct"
		fi
	done
done

# --- 3. names line up --------------------------------------------------------
check_plugin_manifest context-nudge "$root" "$repo"

# --- 4. the plugin registers the hook ------------------------------------------
hooks_json="$root/hooks/hooks.json"
if python3 -c 'import json' >/dev/null 2>&1; then
	command_line=$(
		python3 - "$hooks_json" 2>/dev/null <<'PY'
import json, sys
doc = json.load(open(sys.argv[1]))
groups = doc["hooks"]["UserPromptSubmit"]
entries = [hook for group in groups for hook in group["hooks"]]
assert len(entries) == 1 and entries[0]["type"] == "command"
print(entries[0]["command"])
PY
	)
	# The braces are text for Claude Code to fill in, not for this shell.
	# shellcheck disable=SC2016
	expected='sh "${CLAUDE_PLUGIN_ROOT}/scripts/context-nudge-hook.sh" --plugin'
	if [ "$command_line" = "$expected" ]; then
		pass "plugin registers one UserPromptSubmit hook from its own folder"
	else
		fail "plugin hook registration is not the expected command: '$command_line'"
	fi
else
	printf 'skip - python3 not usable; hooks.json not parsed\n'
fi
for script in context-nudge-hook.sh context-nudge-lib.sh context-nudge-cache.sh context-nudge-statusline.sh; do
	check "ships scripts/$script" [ -f "$root/scripts/$script" ]
done

# --- 5. every setting is documented ----------------------------------------------
settings=$(grep -ohE 'CONTEXT_NUDGE_[A-Z_]+' "$root"/scripts/*.sh "$root/install.sh" | sort -u)
check "the scripts read settings from the environment" [ -n "$settings" ]
for setting in $settings; do
	check "README documents $setting" grep -qF -- "\`$setting\`" "$readme"
done
# The documented field names the scripts depend on.
for field in 'context_window.used_percentage' 'context_window.total_input_tokens' \
	'context_window.context_window_size' 'session_id' 'transcript_path' \
	'systemMessage' 'hookSpecificOutput.additionalContext' 'model.display_name'; do
	check "README cites $field" grep -qF -- "\`$field\`" "$readme"
done
check "README does not present /handoff as required" grep -q 'optional' "$readme"

finish shipped-file
