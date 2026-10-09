#!/bin/sh
# UserPromptSubmit hook: tell the user and the model how full the context
# window is: once on entry to each band, and on every prompt once compaction
# is close.
#
# The hook input carries no context usage, so the percentage comes from the
# file the status-line half writes (context-nudge-cache.sh or
# context-nudge-statusline.sh). Without that file the hook reads the session
# transcript, and only when CONTEXT_NUDGE_WINDOW_SIZE says how large the
# window is. When the usage or the window size is not known the hook says
# nothing.
#
# Output is one JSON object with two messages:
#   systemMessage                         shown to the user: the reading and
#                                         the advice
#   hookSpecificOutput.additionalContext  added to the model's context: one
#                                         sentence of fact, with no instruction
#
# Called with --plugin, it also keeps a copy of the status-line scripts under
# the context-nudge folder, so settings can name a path that does not change
# when the plugin is updated.
#
# Settings are environment variables; see the README.

# The cn_ names come from the sourced context-nudge-lib.sh, which also reads
# the ones set here, and the jq programs are literal text.
# shellcheck disable=SC2154,SC2034,SC2016

set -u

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)
# shellcheck source=/dev/null
. "$here/context-nudge-lib.sh"

# No jq: stay silent. The status line is where that gets reported, once,
# instead of an error on every prompt.
cn_have_jq || exit 0

# One jq run on the hook's stdin for both fields; jq start-up is the main
# cost of this script.
fields=$("$cn_jq" -r "$cn_def_text"'
	(.session_id | text), (.transcript_path | text)' 2>/dev/null) || exit 0
{
	IFS= read -r sid
	IFS= read -r transcript
} <<EOF
$fields
EOF

# Without a session id a repeat cannot be told from a first sighting.
cn_safe_id "${sid:-}" || exit 0
[ -n "$cn_dir" ] || exit 0
[ -d "$cn_dir" ] || mkdir -p "$cn_dir" 2>/dev/null || exit 0

# --- once a day: prune old files, refresh the plugin's script copies ---------
now=$(date +%s)
today=$((now / 86400))
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
if [ "${1:-}" = --plugin ] && [ "$sync_bin" -eq 1 ]; then
	mkdir -p "$bin" 2>/dev/null || :
	for script in context-nudge-lib.sh context-nudge-cache.sh context-nudge-statusline.sh; do
		cmp -s "$here/$script" "$bin/$script" || cp "$here/$script" "$bin/$script" 2>/dev/null || :
	done
fi

# --- how full is the window? ---------------------------------------------------
if ! cn_read_cache "$sid" "$now"; then
	# No status-line record, or one that is too old or has no usage in it.
	# The transcript gives a token count but not the window size, so it is
	# read only when the size has been stated.
	cn_is_uint "${CONTEXT_NUDGE_WINDOW_SIZE:-}" || exit 0
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
fi
cn_assess || exit 0

# --- has this level been announced? --------------------------------------------
state="$cn_dir/$sid.band"
last=0
[ -r "$state" ] && read -r last <"$state"
cn_number "$last" 0
last=$cn_value

if [ "$cn_level" -lt "$last" ]; then
	# Usage fell, after a compaction for example. Re-arm at the lower level
	# and say nothing, so the bands above it are announced again.
	printf '%s\n' "$cn_level" >"$state" 2>/dev/null || :
	exit 0
fi
[ "$cn_level" -gt 0 ] || exit 0
if [ "$cn_level" -eq "$last" ] && [ "$cn_level" -lt 4 ]; then
	exit 0
fi
printf '%s\n' "$cn_level" >"$state" 2>/dev/null || :

# --- the two messages ----------------------------------------------------------
reading="${cn_shown}% used ($((cn_used / 1000))k of $((cn_window / 1000))k tokens) - ${cn_label_text}"

# The advice is for the user. The model gets the reading as one sentence of
# fact, worded so that it cannot be taken for an order.
"$cn_jq" -n --arg reading "$reading" --arg advice "$cn_advice" '{
	systemMessage: ("Context " + $reading + ". " + $advice),
	hookSpecificOutput: {
		hookEventName: "UserPromptSubmit",
		additionalContext: ("CONTEXT NUDGE: the context window is " + $reading
			+ "; this is information only, not an instruction to stop work, and a handoff is written only when the user asks for one, so a one-line suggestion to hand off or compact (the user may have the optional /handoff skill) is the most it calls for.")
	}
}'
exit 0
