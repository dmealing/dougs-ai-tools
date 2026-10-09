#!/bin/sh
# UserPromptSubmit hook: tell the user and the model how full the context
# window is, once on entry to each band and on every prompt near the top.
#
# The hook input carries no context usage, so the percentage comes from the
# file the status-line half writes (context-nudge-cache.sh or
# context-nudge-statusline.sh). Without that file the hook reads the session
# transcript, and only when CONTEXT_NUDGE_WINDOW_SIZE says how large the
# window is. When the percentage is not known the hook says nothing.
#
# Output is one JSON object with two messages:
#   systemMessage                         shown to the user
#   hookSpecificOutput.additionalContext  added to the model's context
#
# Called with --plugin, it also keeps a copy of the status-line scripts under
# the context-nudge folder, so settings can name a path that does not change
# when the plugin is updated.
#
# Settings are environment variables; see the README.

# The cn_ names come from the sourced context-nudge-lib.sh, and the jq programs
# are literal text.
# shellcheck disable=SC2154,SC2016

set -u

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)
# shellcheck source=/dev/null
. "$here/context-nudge-lib.sh"

input=$(cat)

# No jq: stay silent. The status line is where that gets reported, once,
# instead of an error on every prompt.
cn_have_jq || exit 0

# One jq run for both fields; jq start-up is the main cost of this script.
fields=$(printf '%s' "$input" | "$cn_jq" -r '
	def text: if type == "string" then gsub("[\n\r]"; " ") else "" end;
	(.session_id | text), (.transcript_path | text)' 2>/dev/null) || exit 0
{
	IFS= read -r sid
	IFS= read -r transcript
} <<EOF
$fields
EOF

# Without a session id a repeat cannot be told from a first sighting.
cn_safe_id "${sid:-}" || exit 0
mkdir -p "$cn_dir" 2>/dev/null || exit 0

# --- once a day: prune old files, refresh the plugin's script copies ---------
today=$(($(date +%s) / 86400))
last_day=''
[ -r "$cn_dir/.maintained" ] && read -r last_day <"$cn_dir/.maintained"
bin="$cn_dir/bin"
if [ "$last_day" != "$today" ]; then
	printf '%s\n' "$today" >"$cn_dir/.maintained" 2>/dev/null || :
	find "$cn_dir" -type f \( -name '*.band' -o -name '*.usage' -o -name '*.tmp' \) \
		-mtime +30 -exec rm -f {} + 2>/dev/null || :
	sync_bin=1
elif [ ! -f "$bin/context-nudge-statusline.sh" ]; then
	sync_bin=1
else
	sync_bin=0
fi
if [ "${1:-}" = --plugin ] && [ "$sync_bin" -eq 1 ] && [ "$here" != "$bin" ]; then
	mkdir -p "$bin" 2>/dev/null || :
	for script in context-nudge-lib.sh context-nudge-cache.sh context-nudge-statusline.sh; do
		cmp -s "$here/$script" "$bin/$script" || cp "$here/$script" "$bin/$script" 2>/dev/null || :
	done
fi

# --- how full is the window? ---------------------------------------------------
if ! cn_read_cache "$sid"; then
	# No status-line record. The transcript gives a token count but not the
	# window size, and a guessed size gives a wrong percentage.
	cn_is_uint "${CONTEXT_NUDGE_WINDOW_SIZE:-}" || exit 0
	cn_number "$CONTEXT_NUDGE_WINDOW_SIZE" 0
	cn_size=$cn_value
	[ "$cn_size" -gt 0 ] || exit 0
	[ -n "${transcript:-}" ] && [ -r "$transcript" ] || exit 0
	# The last main-conversation reply's input side, the count the reported
	# percentage uses. fromjson? skips a line that is still being written.
	cn_tokens=$(tail -n 200 "$transcript" 2>/dev/null | "$cn_jq" -R -r '
		fromjson?
		| select(type == "object" and .type == "assistant" and .isSidechain != true)
		| .message.usage? | select(type == "object")
		| (.input_tokens // 0) + (.cache_creation_input_tokens // 0)
			+ (.cache_read_input_tokens // 0)' 2>/dev/null | tail -n 1)
	cn_is_uint "$cn_tokens" || exit 0
	cn_pct=$((cn_tokens * 100 / cn_size))
fi
[ -n "$cn_pct" ] || exit 0

# --- which band, and has it been announced? ---------------------------------
cn_load_settings
band=0
for b in $cn_bands; do
	if [ "$cn_pct" -ge "$b" ] && [ "$b" -gt "$band" ]; then band=$b; fi
done
[ "$cn_pct" -lt "$cn_repeat" ] || band=$cn_repeat

state="$cn_dir/$sid.band"
last=0
[ -r "$state" ] && read -r last <"$state"
cn_number "$last" 0
last=$cn_value

if [ "$band" -lt "$last" ]; then
	# Usage fell, after a compaction for example. Re-arm at the lower band
	# and say nothing, so the bands above it are announced again.
	printf '%s\n' "$band" >"$state" 2>/dev/null || :
	exit 0
fi
[ "$band" -gt 0 ] || exit 0
if [ "$band" -eq "$last" ] && [ "$cn_pct" -lt "$cn_repeat" ]; then
	exit 0
fi
printf '%s\n' "$band" >"$state" 2>/dev/null || :

# --- the two messages ----------------------------------------------------------
# The wording follows the percentage, so a custom band list changes when the
# hook speaks and not what it says at a given level.
if [ "$cn_pct" -ge "$cn_repeat" ]; then
	advice='Stop starting new work. Land or park what is open now, then hand off or compact.'
elif [ "$cn_pct" -ge 85 ]; then
	advice='Land what is in flight and move to a fresh session soon: hand off or compact.'
elif [ "$cn_pct" -ge 80 ]; then
	advice='Quality over a window this full is likely dropping. Wrap up the current thread, then hand off or compact.'
elif [ "$cn_pct" -ge "$cn_high" ]; then
	advice='At the next clean break, consider a fresh session: hand off or compact.'
elif [ "$cn_pct" -ge 60 ]; then
	advice='Finish what is open before starting something new.'
else
	advice='Still fine. Avoid starting a large new task in this session.'
fi

cn_label "$cn_pct"
if [ -n "$cn_tokens" ] && [ -n "$cn_size" ]; then
	detail=" ($((cn_tokens / 1000))k of $((cn_size / 1000))k tokens)"
else
	detail=''
fi
message="Context ${cn_pct}% used${detail} - ${cn_label_text}. ${advice}"

guard='This notice is a status readout for the user. On its own it is not an instruction to stop work, and it is not an instruction to write a handoff: do not write or draft one because of it. If this is a clean break, you may offer to hand off or compact in a single line, then wait for the user to answer. State the context percentage in your reply so the user sees it. If the optional handoff skill is installed, the user can ask for it with /handoff.'

"$cn_jq" -n --arg message "$message" --arg guard "$guard" '{
	systemMessage: $message,
	hookSpecificOutput: {
		hookEventName: "UserPromptSubmit",
		additionalContext: ("CONTEXT NUDGE: " + $message + " " + $guard)
	}
}'
exit 0
