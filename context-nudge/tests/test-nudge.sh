#!/bin/sh
# Tests for the prompt hook, the cache writer and the status line, driven by
# the sample inputs in fixtures/. Every case runs against a throwaway config
# directory, so nothing under the real Claude Code configuration is touched.
#
# Run: sh context-nudge/tests/test-nudge.sh

set -u

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)
root=$(dirname -- "$here")
repo=$(dirname -- "$root")
hook="$root/scripts/context-nudge-hook.sh"
cache="$root/scripts/context-nudge-cache.sh"
line="$root/scripts/context-nudge-statusline.sh"
fixtures="$here/fixtures"

# shellcheck source=/dev/null
. "$repo/lib/test-helpers.sh"

work=$(mktemp -d "${TMPDIR:-/tmp}/context-nudge-test.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT INT TERM

# Settings from the caller's environment must not reach the cases.
unset CONTEXT_NUDGE_BANDS CONTEXT_NUDGE_REPEAT_AT CONTEXT_NUDGE_HIGH_AT \
	CONTEXT_NUDGE_LABEL_OK CONTEXT_NUDGE_LABEL_FILLING CONTEXT_NUDGE_LABEL_HIGH \
	CONTEXT_NUDGE_LABEL_CRITICAL CONTEXT_NUDGE_WINDOW_SIZE CONTEXT_NUDGE_JQ
CLAUDE_CONFIG_DIR="$work/cfg"
NO_COLOR=1
export CLAUDE_CONFIG_DIR NO_COLOR
dir="$CLAUDE_CONFIG_DIR/context-nudge"

# --- without jq ------------------------------------------------------------------
# These run first and need no jq themselves.
CONTEXT_NUDGE_JQ="$work/no-such-jq" sh "$hook" <"$fixtures/hook-input.json" >"$work/out" 2>&1
check "hook without jq exits 0" [ $? -eq 0 ]
check "hook without jq prints nothing" [ ! -s "$work/out" ]
CONTEXT_NUDGE_JQ="$work/no-such-jq" sh "$line" <"$fixtures/statusline.json" >"$work/out" 2>&1
check "status line without jq exits 0" [ $? -eq 0 ]
check "status line without jq is one line" [ "$(wc -l <"$work/out" | tr -d ' ')" -eq 1 ]
check "status line without jq names jq" grep -q 'jq not found' "$work/out"
CONTEXT_NUDGE_JQ="$work/no-such-jq" sh "$cache" <"$fixtures/statusline.json" >"$work/out" 2>&1
check "cache writer without jq exits 0" [ $? -eq 0 ]
check "cache writer without jq still passes its input through" cmp -s "$fixtures/statusline.json" "$work/out"
check "nothing is written without jq" [ ! -e "$dir" ]

if ! command -v jq >/dev/null 2>&1; then
	printf 'skip - jq not found; the remaining cases were not run\n'
	finish nudge
	exit 0
fi

# status_json <session> <used_percentage or null> [<input tokens> [<window size>]]
status_json() {
	jq --arg sid "$1" --argjson pct "$2" --argjson tokens "${3:-null}" --argjson size "${4:-200000}" \
		'.session_id = $sid | .context_window.used_percentage = $pct
		 | .context_window.context_window_size = $size
		 | if $tokens != null then .context_window.total_input_tokens = $tokens
		   elif $pct != null then .context_window.total_input_tokens = ($pct * $size / 100)
		   else . end' "$fixtures/statusline.json"
}
# at <session> <percentage>: the status line reports that usage for the session.
at() { status_json "$1" "$2" | sh "$cache" >/dev/null; }
# prompt <session> [<transcript> [<VARIABLE=value>...]]: the user submits a
# prompt, with those settings in the hook's environment; output in $work/out.
# The settings are arguments because a shell need not pass an assignment in
# front of a function call on to the commands the function runs.
prompt() {
	prompt_sid=$1
	prompt_transcript=${2:-/work/sessions/none.jsonl}
	shift
	[ $# -eq 0 ] || shift
	jq --arg sid "$prompt_sid" --arg transcript "$prompt_transcript" \
		'.session_id = $sid | .transcript_path = $transcript' "$fixtures/hook-input.json" |
		env "$@" sh "$hook" >"$work/out" 2>"$work/err"
	status=$?
}
silent() { [ "$status" -eq 0 ] && [ ! -s "$work/out" ] && [ ! -s "$work/err" ]; }
user_message() { jq -r '.systemMessage' "$work/out" 2>/dev/null; }
model_notice() { jq -r '.hookSpecificOutput.additionalContext' "$work/out" 2>/dev/null; }
says() { user_message | grep -q -- "$1"; }
tells_model() { model_notice | grep -q -- "$1"; }
user_not_told() { ! says "$1"; }
coloured() { (unset NO_COLOR && sh "$line" <"$fixtures/statusline.json" | grep -q '\[33m42% context'); }
# spoke <percentage>: one notice, to both the user and the model, for it.
spoke() {
	[ "$status" -eq 0 ] && [ ! -s "$work/err" ] && says "Context $1% used" &&
		model_notice | grep -q "CONTEXT NUDGE: Context $1% used" &&
		[ "$(jq -r '.hookSpecificOutput.hookEventName' "$work/out")" = UserPromptSubmit ]
}

# --- the cache writer ------------------------------------------------------------
sh "$cache" <"$fixtures/statusline.json" >"$work/out" 2>&1
check "cache writer passes its input through unchanged" cmp -s "$fixtures/statusline.json" "$work/out"
check "cache writer records the session's usage" [ "$(cat "$dir/sample-session-0001.usage")" = "42 84000 200000" ]
printf 'not json' | sh "$cache" >"$work/out" 2>&1
check "cache writer passes through input that is not JSON" [ "$(cat "$work/out")" = "not json" ]
status_json '../escape' 50 | sh "$cache" >/dev/null 2>&1
check "a session id with a path in it is not used as a file name" [ ! -e "$CLAUDE_CONFIG_DIR/escape.usage" ]

# --- the status line ---------------------------------------------------------------
check "status line shows model, percentage and label" \
	[ "$(sh "$line" <"$fixtures/statusline.json")" = "Opus | 42% context | filling" ]
check "status line below the first band" \
	[ "$(status_json line-a 12 | sh "$line")" = "Opus | 12% context | ok" ]
check "status line in the high band" \
	[ "$(status_json line-a 70 | sh "$line")" = "Opus | 70% context | high" ]
check "status line at the every-prompt threshold" \
	[ "$(status_json line-a 93 | sh "$line")" = "Opus | 93% context | critical" ]
check "status line with no usage yet" \
	[ "$(jq '.context_window = null' "$fixtures/statusline.json" | sh "$line")" = "Opus | context --" ]
check "status line records usage as the cache writer does" [ "$(cat "$dir/line-a.usage")" = "93 186000 200000" ]
check "status line labels are configurable" \
	[ "$(status_json line-a 45 | CONTEXT_NUDGE_LABEL_FILLING=warm sh "$line")" = "Opus | 45% context | warm" ]
check "status line colours unless NO_COLOR is set" \
	coloured

# --- silence below the first band ----------------------------------------------------
at quiet 0
prompt quiet
check "silent at 0 percent" silent
at quiet 39
prompt quiet
check "silent at 39 percent" silent

# --- one notice per band per session -------------------------------------------------
at s1 40
prompt s1
check "speaks on entering the first band" spoke 40
check "the first notice is mild" says "filling. Still fine"
check "the notice gives the token counts" says "(80k of 200k tokens)"
check "the model is told the notice is not an instruction to stop or hand off" \
	tells_model "not an instruction to stop work, and it is not an instruction to write a handoff"
check "the model is told it may offer once and wait" \
	tells_model "offer to hand off or compact in a single line, then wait"
check "the handoff skill is named only as optional" \
	tells_model "If the optional handoff skill is installed"
check "the user message does not name /handoff" user_not_told /handoff
prompt s1
check "silent on the next prompt in the same band" silent
at s1 47
prompt s1
check "silent higher up in the same band" silent

notices=0
for pct in 50 55 60 61 70 79 80 84 85 89; do
	at s1 "$pct"
	prompt s1
	[ -s "$work/out" ] && notices=$((notices + 1))
done
check "five more bands give exactly five more notices" [ "$notices" -eq 5 ]
at s2 62
prompt s2
check "another session gets its own notice" spoke 62
check "a session that starts high is told once" says "Finish what is open"
prompt s2
check "and only once" silent

# --- wording firms up -----------------------------------------------------------------
at w 72
prompt w
check "70s: suggests a fresh session at a clean break" says "high. At the next clean break"
at w 81
prompt w
check "80s: says to wrap up" says "Wrap up the current thread"
at w 86
prompt w
check "85 up: says to land what is in flight" says "Land what is in flight"

# --- every prompt from the threshold ---------------------------------------------------
at w 90
prompt w
check "speaks at the every-prompt threshold" spoke 90
check "the top notice is the firmest" says "critical. Stop starting new work"
prompt w
check "speaks again on the next prompt" spoke 90
at w 97
prompt w
check "and again higher up" spoke 97

# --- usage falls ------------------------------------------------------------------------
at w 45
prompt w
check "silent when usage falls to a band already announced" silent
at w 52
prompt w
check "bands above the new level are announced again" spoke 52

# --- configurable bands, threshold and labels ------------------------------------------
at c 25
prompt c
check "25 percent is silent by default" silent
prompt c "" CONTEXT_NUDGE_BANDS='20,30 75'
check "a lower first band speaks earlier" spoke 25
at c 45
prompt c "" CONTEXT_NUDGE_BANDS='20,30 75'
check "bands are announced once each" spoke 45
at c 60
prompt c "" CONTEXT_NUDGE_BANDS='20,30 75'
check "no notice between configured bands" silent
at c 76
prompt c "" CONTEXT_NUDGE_BANDS='20,30 75' CONTEXT_NUDGE_LABEL_HIGH=hot
check "labels in the notice are configurable" says "76% used (152k of 200k tokens) - hot\\."
at e 81
prompt e "" CONTEXT_NUDGE_HIGH_AT=82
check "the advice never runs ahead of the label" says "filling. Finish what is open"
at c 78
prompt c "" CONTEXT_NUDGE_BANDS='20,30 75' CONTEXT_NUDGE_REPEAT_AT=78
check "a lower every-prompt threshold speaks" spoke 78
prompt c "" CONTEXT_NUDGE_BANDS='20,30 75' CONTEXT_NUDGE_REPEAT_AT=78
check "and repeats" spoke 78
at d 45
prompt d "" CONTEXT_NUDGE_BANDS='nonsense'
check "a band list with no numbers falls back to the defaults" spoke 45

# --- hook and status line agree ----------------------------------------------------------
# Reported percentage, a fraction, and the fall-back to tokens over window size.
agree() {
	# agree <description> <session> <used_percentage> <tokens> <size>
	shown=$(status_json "$2" "$3" "$4" "$5" | sh "$line" | sed -n 's/.* \([0-9]*\)% context.*/\1/p')
	prompt "$2" "" CONTEXT_NUDGE_BANDS=1
	told=$(user_message | sed -n 's/^Context \([0-9]*\)% used.*/\1/p')
	if [ -n "$shown" ] && [ "$shown" = "$told" ] && [ "$shown" = "$6" ]; then
		pass "$1"
	else
		fail "$1: status line '$shown', hook '$told', expected '$6'"
	fi
}
agree "hook and status line agree on a reported percentage" a1 42 84000 200000 42
agree "the reported percentage wins over the token counts" a2 42 150000 200000 42
agree "a fractional percentage is rounded down by both" a3 41.9 84000 200000 41
agree "with none reported, both use tokens over window size" a4 null 130000 200000 65
agree "a larger window gives the matching percentage" a5 null 450000 1000000 45

# --- no status-line record ------------------------------------------------------------------
prompt nocache "$fixtures/transcript.jsonl"
check "no record and no window size: silent" silent
check "no record: nothing is guessed into the state" [ ! -e "$dir/nocache.band" ]
prompt nocache "$fixtures/transcript.jsonl" CONTEXT_NUDGE_WINDOW_SIZE=200000
check "with a stated window size the transcript is used" spoke 45
check "the transcript count is the last main reply's input side" says "(90k of 200k tokens)"
prompt nocache2 "$work/missing.jsonl" CONTEXT_NUDGE_WINDOW_SIZE=200000
check "a stated window size and no transcript: silent" silent
status_json unknown null null null | sh "$cache" >/dev/null
prompt unknown "$fixtures/transcript.jsonl"
check "a record with no percentage: silent" silent
prompt unknown "$fixtures/transcript.jsonl" CONTEXT_NUDGE_WINDOW_SIZE=200000
check "a record with no percentage does not block the transcript" spoke 45
(
	unset CLAUDE_CONFIG_DIR HOME
	sh "$cache" <"$fixtures/statusline.json" >"$work/out" 2>"$work/err"
)
check "with no config directory and no HOME the cache writer still passes through" \
	cmp -s "$fixtures/statusline.json" "$work/out"
check "and reports no error" [ ! -s "$work/err" ]

# --- input the hook cannot use ------------------------------------------------------------------
printf 'not json' | sh "$hook" >"$work/out" 2>"$work/err"
status=$?
check "input that is not JSON: silent" silent
printf '{"prompt":"hello"}' | sh "$hook" >"$work/out" 2>"$work/err"
status=$?
check "input with no session id: silent" silent

# --- pruning ----------------------------------------------------------------------------------
old() { touch -t 202001010000 "$1"; }
printf '50\n' >"$dir/ancient.band"
printf '50 100000 200000\n' >"$dir/ancient.usage"
printf 'x\n' >"$dir/ancient.123.tmp"
printf 'keep\n' >"$dir/notes.txt"
old "$dir/ancient.band"
old "$dir/ancient.usage"
old "$dir/ancient.123.tmp"
old "$dir/notes.txt"
prompt quiet
check "nothing is pruned twice in one day" [ -e "$dir/ancient.band" ]
printf '1\n' >"$dir/.maintained"
prompt quiet
check "old state is pruned" [ ! -e "$dir/ancient.band" ]
check "old usage records are pruned" [ ! -e "$dir/ancient.usage" ]
check "old leftovers are pruned" [ ! -e "$dir/ancient.123.tmp" ]
check "recent files are kept" [ -e "$dir/s1.band" ]
check "files that are not the tool's are kept" [ -e "$dir/notes.txt" ]
check "the hook does not copy scripts unless run as a plugin" [ ! -e "$dir/bin" ]

# --- run as a plugin ------------------------------------------------------------------------------
jq '.session_id = "quiet"' "$fixtures/hook-input.json" | sh "$hook" --plugin >"$work/out" 2>&1
check "as a plugin the hook keeps a copy of the status-line scripts" \
	cmp -s "$line" "$dir/bin/context-nudge-statusline.sh"
check "the copy runs from there" \
	[ "$(sh "$dir/bin/context-nudge-statusline.sh" <"$fixtures/statusline.json")" = "Opus | 42% context | filling" ]
check "the copy's cache writer is there too" cmp -s "$cache" "$dir/bin/context-nudge-cache.sh"

finish nudge
