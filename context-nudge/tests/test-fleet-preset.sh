#!/bin/sh
# Tests for the fleet preset (fleet-preset.settings.json): the settings in it,
# run through the real hook and status-line scripts, give a percentage-only
# ladder that starts at 40 percent whatever the window size. Every case runs
# against a throwaway config directory.
#
# Run: sh context-nudge/tests/test-fleet-preset.sh

set -u

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)
root=$(dirname -- "$here")
repo=$(dirname -- "$root")
hook="$root/scripts/context-nudge-hook.sh"
cache="$root/scripts/context-nudge-cache.sh"
preset="$root/fleet-preset.settings.json"
fixtures="$here/fixtures"

# shellcheck source=/dev/null
. "$repo/lib/test-helpers.sh"

if ! command -v jq >/dev/null 2>&1; then
	printf 'skip - jq not found; the fleet preset was not run\n'
	finish fleet-preset
	exit 0
fi

work=$(mktemp -d "${TMPDIR:-/tmp}/context-nudge-fleet-test.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT INT TERM

unset CONTEXT_NUDGE_BAND1_PERCENT CONTEXT_NUDGE_BAND1_TOKENS \
	CONTEXT_NUDGE_BAND2_PERCENT CONTEXT_NUDGE_BAND2_TOKENS \
	CONTEXT_NUDGE_BAND3_PERCENT CONTEXT_NUDGE_BAND3_TOKENS \
	CONTEXT_NUDGE_REPEAT_MARGIN CONTEXT_NUDGE_WINDOW_SIZE CONTEXT_NUDGE_COMPACT_WINDOW \
	CONTEXT_NUDGE_JQ CONTEXT_NUDGE_MAX_AGE
CLAUDE_CONFIG_DIR="$work/cfg"
NO_COLOR=1
export CLAUDE_CONFIG_DIR NO_COLOR

quiet_jq() { jq -e "$@" >/dev/null; }
check "the preset is valid JSON with an env object" quiet_jq '.env | type == "object"' "$preset"
check "every value in the preset is a string, as settings.json env requires" \
	quiet_jq '[.env[] | type == "string"] | all' "$preset"
check "the preset sets nothing but nudge settings" \
	quiet_jq '[.env | keys[] | startswith("CONTEXT_NUDGE_")] | all' "$preset"

# preset_env: the preset's settings as NAME=value lines.
preset_env() { jq -r '.env | to_entries[] | "\(.key)=\(.value)"' "$preset"; }

# reading <session> <window> <tokens> <preset|default>: one prompt at that
# usage; the hook's output is left in $work/out.
reading() {
	jq --arg sid "$1" --argjson size "$2" --argjson tokens "$3" \
		'.session_id = $sid | .context_window.used_percentage = ($tokens * 100 / $size | floor)
		 | .context_window.total_input_tokens = $tokens
		 | .context_window.context_window_size = $size' "$fixtures/statusline.json" | sh "$cache" >/dev/null
	set -- "$1" "$4"
	jq --arg sid "$1" '.session_id = $sid' "$fixtures/hook-input.json" >"$work/input"
	if [ "$2" = preset ]; then
		# shellcheck disable=SC2046
		env $(preset_env) sh "$hook" <"$work/input" >"$work/out" 2>/dev/null
	else
		sh "$hook" <"$work/input" >"$work/out" 2>/dev/null
	fi
}
said() { jq -r '.systemMessage // empty' "$work/out" 2>/dev/null; }
silent() { [ ! -s "$work/out" ]; }
says_label() { said | grep -q -- "$1"; }

# --- a 1,000,000-token window: the default token triggers would fire at 10 percent
reading w1 1000000 150000 default
check "without the preset a 1M window speaks at 15 percent (the problem the preset fixes)" says_label 'filling'
reading w2 1000000 150000 preset
check "with the preset a 1M window is silent at 15 percent" silent
reading w3 1000000 390000 preset
check "with the preset a 1M window is silent at 39 percent" silent
reading w4 1000000 400000 preset
check "the first notice is at 40 percent" says_label 'filling'
check "the first notice carries the percentage" says_label '40% used'

# --- the ladder climbs with the percentage, a notice once per band --------------------
reading w5 200000 80000 preset
check "a 200k window: the first notice at 40 percent" says_label 'filling'
reading w5 200000 90000 preset
check "the same band is not announced twice" silent
reading w5 200000 120000 preset
check "60 percent: the second band" says_label 'high'
reading w5 200000 160000 preset
check "80 percent: the third band" says_label 'very high'
reading w5 200000 190000 preset
check "near compaction: critical" says_label 'critical'
reading w5 200000 191000 preset
check "near compaction it repeats on every prompt" says_label 'critical'

# --- the notice never tells the model to write a handoff ----------------------------------
reading w6 200000 80000 preset
model_sentence() { jq -r '.hookSpecificOutput.additionalContext' "$work/out"; }
check "the model's sentence says a handoff is written only when the user asks" \
	sh -c "$(model_sentence | grep -qF 'a handoff is written only when the user asks for one' && echo true || echo false)"
check "the model's sentence says it is information only" \
	sh -c "$(model_sentence | grep -qF 'information only' && echo true || echo false)"

# --- the page and the README point at it -----------------------------------------------------
check "FLEET.md ships" [ -f "$root/FLEET.md" ]
check "FLEET.md names the preset file" grep -qF 'fleet-preset.settings.json' "$root/FLEET.md"
check "the README links the fleet page" grep -qF 'FLEET.md' "$root/README.md"

finish fleet-preset
