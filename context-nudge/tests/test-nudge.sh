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
unset CONTEXT_NUDGE_BAND1_PERCENT CONTEXT_NUDGE_BAND1_TOKENS \
	CONTEXT_NUDGE_BAND2_PERCENT CONTEXT_NUDGE_BAND2_TOKENS \
	CONTEXT_NUDGE_BAND3_PERCENT CONTEXT_NUDGE_BAND3_TOKENS \
	CONTEXT_NUDGE_REPEAT_MARGIN CONTEXT_NUDGE_WINDOW_SIZE CONTEXT_NUDGE_COMPACT_WINDOW \
	CONTEXT_NUDGE_LABEL_OK CONTEXT_NUDGE_LABEL_BAND1 CONTEXT_NUDGE_LABEL_BAND2 \
	CONTEXT_NUDGE_LABEL_BAND3 CONTEXT_NUDGE_LABEL_CRITICAL CONTEXT_NUDGE_JQ \
	CONTEXT_NUDGE_MAX_AGE
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

# status_json <session> <used_percentage or null> <input tokens or null> [<window size or null>]
status_json() {
	jq --arg sid "$1" --argjson pct "$2" --argjson tokens "$3" --argjson size "${4:-200000}" \
		'.session_id = $sid | .context_window.used_percentage = $pct
		 | .context_window.total_input_tokens = $tokens
		 | .context_window.context_window_size = $size' "$fixtures/statusline.json"
}
# at <session> <thousands of tokens> [<window size>]: the status line reports
# that usage for the session, with the percentage Claude Code would report.
at() {
	at_size=${3:-200000}
	status_json "$1" "$(($2 * 100000 / at_size))" "$(($2 * 1000))" "$at_size" | sh "$cache" >/dev/null
}
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
model_not_told() { ! tells_model "$1"; }
# recorded <session>: the percentage, tokens and window size on record.
recorded() { cut -d' ' -f1-3 "$dir/$1.usage"; }
coloured() { (unset NO_COLOR && sh "$line" <"$fixtures/statusline.json" | grep -q '\[33m42% context'); }
# spoke <percentage>: one notice, to both the user and the model, for it.
spoke() {
	[ "$status" -eq 0 ] && [ ! -s "$work/err" ] && says "Context $1% used" &&
		model_notice | grep -q "CONTEXT NUDGE: the context window is $1% used" &&
		[ "$(jq -r '.hookSpecificOutput.hookEventName' "$work/out")" = UserPromptSubmit ]
}
# shows <expected status line> <status_json arguments...> [-- <VARIABLE=value>...]
shows() {
	shows_want=$1
	shows_sid=$2
	shows_pct=$3
	shows_tokens=$4
	shows_size=$5
	shift 5
	shows_got=$(status_json "$shows_sid" "$shows_pct" "$shows_tokens" "$shows_size" | env "$@" sh "$line")
	[ "$shows_got" = "$shows_want" ]
}

# --- the cache writer ------------------------------------------------------------
sh "$cache" <"$fixtures/statusline.json" >"$work/out" 2>&1
check "cache writer passes its input through unchanged" cmp -s "$fixtures/statusline.json" "$work/out"
check "cache writer records the session's usage" [ "$(recorded sample-session-0001)" = "42 84000 200000" ]
printf 'not json' | sh "$cache" >"$work/out" 2>&1
check "cache writer passes through input that is not JSON" [ "$(cat "$work/out")" = "not json" ]
(
	unset CLAUDE_CONFIG_DIR HOME
	sh "$cache" <"$fixtures/statusline.json" >"$work/out" 2>"$work/err"
)
check "with no config directory and no HOME the cache writer still passes through" \
	cmp -s "$fixtures/statusline.json" "$work/out"
check "and reports no error" [ ! -s "$work/err" ]

# --- session ids are checked before any path is built -------------------------------
for bad in '..' '.' '.hidden' 'a/b' '../escape' 'a b' ''; do
	before=$(find "$work" | wc -l)
	status_json "$bad" 95 190000 | sh "$cache" >/dev/null 2>&1
	jq --arg sid "$bad" '.session_id = $sid' "$fixtures/hook-input.json" | sh "$hook" >"$work/out" 2>&1
	if [ "$(find "$work" | wc -l)" -eq "$before" ] && [ ! -s "$work/out" ]; then
		pass "session id '$bad' is rejected: nothing written, nothing said"
	else
		fail "session id '$bad' was used"
	fi
done
status_json ok.id_1-A 95 190000 | sh "$cache" >/dev/null 2>&1
check "a session id of letters, digits, dots, hyphens and underscores is used" [ -f "$dir/ok.id_1-A.usage" ]

# --- the status line ---------------------------------------------------------------
check "status line shows model, percentage and label" \
	[ "$(sh "$line" <"$fixtures/statusline.json")" = "Opus | 42% context | filling" ]
check "status line below the first band" shows "Opus | 12% context | ok" line-a 12 24000 200000
check "status line in the second band" shows "Opus | 60% context | high" line-a 60 120000 200000
check "status line in the third band" shows "Opus | 80% context | very high" line-a 80 160000 200000
check "status line near compaction" shows "Opus | 93% context | critical" line-a 93 186000 200000
check "status line records usage as the cache writer does" [ "$(recorded line-a)" = "93 186000 200000" ]
check "status line with no usage yet" \
	[ "$(jq '.context_window = null' "$fixtures/statusline.json" | sh "$line")" = "Opus | context --" ]
check "status line with no window size reports no figure" shows "Opus | context --" line-a 42 84000 null
check "status line labels are configurable" \
	shows "Opus | 45% context | warm" line-a 45 90000 200000 CONTEXT_NUDGE_LABEL_BAND1=warm
check "status line colours unless NO_COLOR is set" coloured

# --- only the context window's own percentage is read ------------------------------
# rate_limits holds other fields named used_percentage.
limits='{"five_hour": {"used_percentage": 77, "resets_at": 1}, "seven_day": {"used_percentage": 88, "resets_at": 2}}'
check "a rate-limit percentage is not taken for the context percentage" \
	[ "$(status_json rl 12 24000 | jq --argjson limits "$limits" '.rate_limits = $limits' | sh "$line")" = "Opus | 12% context | ok" ]
check "a null context percentage is unknown, whatever rate_limits says" \
	[ "$(status_json rl null null | jq --argjson limits "$limits" '.rate_limits = $limits' | sh "$line")" = "Opus | context --" ]
check "and nothing is recorded as its percentage" [ "$(recorded rl)" = "- - 200000" ]
check "a percentage that is not a number is unknown" shows "Opus | context --" rl '"77"' null 200000

# --- silence below the first band ----------------------------------------------------
at quiet 0
prompt quiet
check "silent with an empty window" silent
at quiet 79
prompt quiet
check "silent at 39 percent of a 200K window" silent

# --- a 200K window: the percentages come first ------------------------------------------
at s1 80
prompt s1
check "200K window: first notice at 40 percent, before 100K tokens" spoke 40
check "the first notice is mild" says "filling. Still fine"
check "the notice gives the token counts against the real window" says "(80k of 200k tokens)"
check "the model is told the notice is information only" tells_model "this is information only, not an instruction to stop work"
check "the model is told a handoff is written only when the user asks" \
	tells_model "a handoff is written only when the user asks for one"
check "the model may suggest a handoff or compacting in one line" \
	tells_model "a one-line suggestion to hand off or compact"
check "the handoff skill is named only as optional" tells_model "the user may have the optional /handoff skill"
check "the user message does not name /handoff" user_not_told /handoff
check "the advice goes to the user only" model_not_told "Still fine"
check "the model's notice is one sentence" [ "$(model_notice | tr -cd '.!?' | wc -c | tr -d ' ')" -eq 1 ]
prompt s1
check "silent on the next prompt in the same band" silent
at s1 110
prompt s1
check "silent higher up in the same band, past the band's token count" silent
at s1 120
prompt s1
check "200K window: second notice at 60 percent" spoke 60
check "the second notice suggests a handoff or a compact" says "high. Finish what is open.*A handoff or a compact"
prompt s1
check "the second notice comes once" silent
at s1 160
prompt s1
check "200K window: third notice at 80 percent" spoke 80
check "the third notice says to wrap up" says "very high. Quality.*Wrap up the current thread"
at s1 175
prompt s1
check "silent between the third band and the margin" silent

notices=0
for used in 10 50 79 80 81 100 119 120 130 159 160 170 179; do
	at count "$used"
	prompt count
	[ -s "$work/out" ] && notices=$((notices + 1))
done
check "three bands give exactly three notices on the way up" [ "$notices" -eq 3 ]
at s2 125
prompt s2
check "another session gets its own notice" spoke 62
check "a session that starts high is told once, at its level" says "high. Finish what is open"
prompt s2
check "and only once" silent

# --- every prompt once compaction is close ------------------------------------------------
at s1 180
prompt s1
check "200K window: speaks within 10 percent of compaction" spoke 90
check "the top notice is the firmest" says "critical. Compaction is close. Stop starting new work"
prompt s1
check "speaks again on the next prompt" spoke 90
at s1 195
prompt s1
check "and again higher up" spoke 97

# --- usage falls ------------------------------------------------------------------------
at s1 90
prompt s1
check "silent when usage falls to a band already announced" silent
at s1 125
prompt s1
check "bands above the new level are announced again" spoke 62

# --- a 1M window: the token counts come first ------------------------------------------------
at big 99 1000000
prompt big
check "1M window: silent at 99K tokens" silent
at big 100 1000000
prompt big
check "1M window: first notice at 100K tokens, at 10 percent" spoke 10
check "the 1M reading is against the real window" says "(100k of 1000k tokens) - filling"
at big 199 1000000
prompt big
check "1M window: silent up to the second band" silent
at big 200 1000000
prompt big
check "1M window: second notice at 200K tokens" spoke 20
at big 300 1000000
prompt big
check "1M window: third notice at 300K tokens" spoke 30
at big 899 1000000
prompt big
check "1M window: silent from the third band to the margin" silent
at big 900 1000000
prompt big
check "1M window: every prompt within 10 percent of compaction" spoke 90
prompt big
check "1M window: and repeats" spoke 90

# --- every threshold is adjustable ---------------------------------------------------------
at c 50
prompt c
check "25 percent is silent by default" silent
prompt c "" CONTEXT_NUDGE_BAND1_PERCENT=25
check "a lower first percentage speaks earlier" spoke 25
at c2 50
prompt c2 "" CONTEXT_NUDGE_BAND1_TOKENS=50000
check "a lower first token count speaks earlier" spoke 25
at c3 90
prompt c3 "" CONTEXT_NUDGE_BAND1_PERCENT=0
check "a percentage of 0 turns that trigger off" silent
at c3 100
prompt c3 "" CONTEXT_NUDGE_BAND1_PERCENT=0
check "and leaves the token trigger" spoke 50
at c4 150
prompt c4 "" CONTEXT_NUDGE_BAND1_PERCENT=0 CONTEXT_NUDGE_BAND1_TOKENS=0 \
	CONTEXT_NUDGE_BAND2_PERCENT=0 CONTEXT_NUDGE_BAND2_TOKENS=0
check "both triggers at 0 turn a band off" silent
at c5 130
prompt c5 "" CONTEXT_NUDGE_BAND2_PERCENT=70 CONTEXT_NUDGE_BAND2_TOKENS=0
check "a higher second percentage holds the second band back" says "filling. Still fine"
at c5 140
prompt c5 "" CONTEXT_NUDGE_BAND2_PERCENT=70 CONTEXT_NUDGE_BAND2_TOKENS=0
check "until it is reached" spoke 70
at c6 150
prompt c6 "" CONTEXT_NUDGE_BAND3_PERCENT=75 CONTEXT_NUDGE_LABEL_BAND3=hot
check "the third band and its label are adjustable" says "75% used (150k of 200k tokens) - hot\\."
at c7 170
prompt c7
prompt c7 "" CONTEXT_NUDGE_REPEAT_MARGIN=15
check "a wider margin starts the every-prompt notices sooner" spoke 85
prompt c7 "" CONTEXT_NUDGE_REPEAT_MARGIN=15
check "and they repeat" spoke 85
at c8 45
prompt c8 "" CONTEXT_NUDGE_BAND1_PERCENT=nonsense
check "a setting that is not a number falls back to its default" silent

# --- an override for the context maximum ------------------------------------------------------
at o 150 1000000
prompt o "" CONTEXT_NUDGE_WINDOW_SIZE=200000
check "a stated maximum replaces the reported one" spoke 75
check "and the reading is against it" says "(150k of 200k tokens) - high"
check "the status line uses the stated maximum too" \
	shows "Opus | 75% context | high" o2 15 150000 1000000 CONTEXT_NUDGE_WINDOW_SIZE=200000

# --- a smaller auto-compact window -------------------------------------------------------------
at k 100 1000000
prompt k "" CONTEXT_NUDGE_COMPACT_WINDOW=250000
check "first band below the compaction point still speaks" spoke 10
at k 210 1000000
prompt k "" CONTEXT_NUDGE_COMPACT_WINDOW=250000
check "second band below the margin still speaks" says "21% used (210k of 1000k tokens) - high"
at k 224 1000000
prompt k "" CONTEXT_NUDGE_COMPACT_WINDOW=250000
check "silent up to the margin of the compact window" silent
at k 225 1000000
prompt k "" CONTEXT_NUDGE_COMPACT_WINDOW=250000
check "every prompt within 10 percent of the compact window" says "22% used (225k of 1000k tokens) - critical"
at k2 300 1000000
prompt k2 "" CONTEXT_NUDGE_COMPACT_WINDOW=250000
check "the third band, at 300K, sits above the compaction point and is dropped" \
	says "critical. Compaction is close"
check "the status line agrees that the band is dropped" \
	shows "Opus | 22% context | high" k3 22 224000 1000000 CONTEXT_NUDGE_COMPACT_WINDOW=250000
at k4 221 1000000
prompt k4 "" CONTEXT_NUDGE_COMPACT_WINDOW=250000 CONTEXT_NUDGE_BAND3_TOKENS=220000
check "a third band moved below the margin is kept" says "very high"
check "a compact window larger than the maximum is ignored" \
	shows "Opus | 93% context | critical" k5 93 186000 200000 CONTEXT_NUDGE_COMPACT_WINDOW=900000

# --- hook and status line agree ----------------------------------------------------------
agree() {
	# agree <description> <session> <used_percentage> <tokens> <size> <expected>
	shown=$(status_json "$2" "$3" "$4" "$5" | sh "$line" | sed -n 's/.* \([0-9]*\)% context.*/\1/p')
	prompt "$2" "" CONTEXT_NUDGE_BAND1_PERCENT=1
	told=$(user_message | sed -n 's/^Context \([0-9]*\)% used.*/\1/p')
	if [ -n "$shown" ] && [ "$shown" = "$told" ] && [ "$shown" = "$6" ]; then
		pass "$1"
	else
		fail "$1: status line '$shown', hook '$told', expected '$6'"
	fi
}
agree "hook and status line agree on a reported percentage" a1 42 84000 200000 42
agree "the reported percentage wins over the token counts" a2 42 90000 200000 42
agree "a fractional percentage is rounded down by both" a3 41.9 84000 200000 41
agree "with none reported, both use tokens over window size" a4 null 130000 200000 65
agree "a larger window gives the matching percentage" a5 null 450000 1000000 45
agree "with no token count, both use the reported percentage" a6 55 null 200000 55

# --- a record that is too old ------------------------------------------------------------
# age <session> <seconds>: makes the session's record that many seconds old.
age() {
	read -r a_pct a_tokens a_size a_written <"$dir/$1.usage"
	printf '%s %s %s %s\n' "$a_pct" "$a_tokens" "$a_size" "$((a_written - $2))" >"$dir/$1.usage"
}
at stale 130
age stale 3500
prompt stale
check "a record under an hour old is used" spoke 65
at stale2 130
age stale2 3700
prompt stale2
check "a record over an hour old is ignored" silent
check "an ignored record announces no band" [ ! -e "$dir/stale2.band" ]
prompt stale2 "" CONTEXT_NUDGE_MAX_AGE=7200
check "the age limit is configurable" spoke 65
at stale3 130
age stale3 100
prompt stale3 "" CONTEXT_NUDGE_MAX_AGE=60
check "a shorter age limit ignores a younger record" silent
age stale3 999999
prompt stale3 "" CONTEXT_NUDGE_MAX_AGE=0
check "an age limit of 0 turns the check off" spoke 65
printf '65 130000 200000\n' >"$dir/undated.usage"
prompt undated
check "a record with no time in it is ignored" silent

# --- no status-line record ------------------------------------------------------------------
prompt nocache "$fixtures/transcript.jsonl"
check "no record and no stated window size: silent" silent
check "no record: nothing is guessed into the state" [ ! -e "$dir/nocache.band" ]
prompt nocache "$fixtures/transcript.jsonl" CONTEXT_NUDGE_WINDOW_SIZE=200000
check "with a stated window size the transcript is used" spoke 45
check "the transcript count is the last main reply's input side" says "(90k of 200k tokens)"
prompt nocache2 "$work/missing.jsonl" CONTEXT_NUDGE_WINDOW_SIZE=200000
check "a stated window size and no transcript: silent" silent
status_json unknown null null null | sh "$cache" >/dev/null
prompt unknown "$fixtures/transcript.jsonl"
check "a record with no usage and no window size: silent" silent
prompt unknown "$fixtures/transcript.jsonl" CONTEXT_NUDGE_WINDOW_SIZE=200000
check "a record with no usage does not block the transcript" spoke 45
status_json nosize 45 90000 null | sh "$cache" >/dev/null
prompt nosize
check "usage with no window size: silent, never an assumed size" silent
at stale4 130
age stale4 3700
prompt stale4 "$fixtures/transcript.jsonl" CONTEXT_NUDGE_WINDOW_SIZE=200000
check "an old record gives way to the transcript when the window size is stated" spoke 45

# --- input the hook cannot use ------------------------------------------------------------------
printf 'not json' | sh "$hook" >"$work/out" 2>"$work/err"
status=$?
check "input that is not JSON: silent" silent
printf '{"prompt":"hello"}' | sh "$hook" >"$work/out" 2>"$work/err"
status=$?
check "input with no session id: silent" silent

# --- pruning ----------------------------------------------------------------------------------
old() { touch -t 202001010000 "$1"; }
printf '2\n' >"$dir/ancient.band"
printf '50 100000 200000 1\n' >"$dir/ancient.usage"
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
