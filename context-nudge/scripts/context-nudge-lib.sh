#!/bin/sh
# Shared by the context-nudge scripts: source it, do not run it.
#
# One implementation of everything the prompt hook, the cache writer and the
# status line have in common: where files live, how the context percentage is
# worked out from the status-line JSON, the bands and the label words.
#
# POSIX sh; runs on stock macOS (bash 3.2, BSD userland) and GNU/Linux.
# jq is the one dependency. Nothing here runs it without checking cn_have_jq.

# The scripts that source this file read the names it sets.
# shellcheck disable=SC2034

# Empty when neither variable says where the configuration is: the scripts then
# record and announce nothing, instead of writing under the root folder.
if [ -n "${CLAUDE_CONFIG_DIR:-}" ]; then
	cn_dir="$CLAUDE_CONFIG_DIR/context-nudge"
elif [ -n "${HOME:-}" ]; then
	cn_dir="$HOME/.claude/context-nudge"
else
	cn_dir=''
fi
cn_jq=${CONTEXT_NUDGE_JQ:-jq}

cn_have_jq() { command -v "$cn_jq" >/dev/null 2>&1; }

# cn_is_uint <text>: a whole number short enough for shell arithmetic.
cn_is_uint() {
	case "${1:-}" in '' | *[!0-9]*) return 1 ;; esac
	[ "${#1}" -le 12 ]
}

# cn_number <text> <default>: sets $cn_value to the text when it is a whole
# number, else to the default. Leading zeros are dropped, because the shell
# would read them as octal.
cn_number() {
	cn_value=$1
	cn_is_uint "$cn_value" || cn_value=$2
	while :; do
		case "$cn_value" in
		0?*) cn_value=${cn_value#0} ;;
		*) break ;;
		esac
	done
}

# cn_safe_id <session id>: usable as a file name. Letters, digits, dots,
# hyphens and underscores only, and no leading dot, so it can hold no path
# separator and cannot be "." or "..". Check it before building any path.
cn_safe_id() {
	case "${1:-}" in '' | .* | *[!A-Za-z0-9._-]*) return 1 ;; esac
}

# --- bands -------------------------------------------------------------------

# cn_assess: works out where the session stands, from $cn_pct, $cn_tokens and
# $cn_size (set by cn_parse_usage or cn_read_cache) and the environment. Sets
#   $cn_window  the context maximum, in tokens
#   $cn_used    the tokens in the window
#   $cn_shown   the percentage of the maximum in use
#   $cn_level   0 below the first band, 1 to 3 for the band reached, 4 once
#               within the margin of the compaction point
#   $cn_label_text  the word for that level
# Fails, setting none of them, when the maximum or the usage is not known:
# nothing is ever reported against an assumed window size.
#
# A band is reached at its percentage of the maximum or at its token count,
# whichever comes first. A band whose point is at or beyond the start of the
# margin is dropped, so nothing is announced at or above compaction.
cn_assess() {
	cn_number "${CONTEXT_NUDGE_WINDOW_SIZE:-}" 0
	if [ "$cn_value" -gt 0 ]; then
		# A stated maximum replaces the reported one, and the reported
		# percentage with it.
		cn_window=$cn_value
		cn_reported=''
	else
		cn_window=$cn_size
		cn_reported=$cn_pct
	fi
	cn_is_uint "$cn_window" && [ "$cn_window" -gt 0 ] || return 1

	cn_used=$cn_tokens
	if [ -z "$cn_used" ]; then
		# Only a percentage was reported: turn it into tokens of the real window.
		cn_is_uint "$cn_pct" && cn_is_uint "$cn_size" || return 1
		cn_used=$((cn_pct * cn_size / 100))
	fi
	cn_shown=${cn_reported:-$((cn_used * 100 / cn_window))}

	# Compaction happens at the maximum, or sooner when a smaller auto-compact
	# window is set.
	cn_compact=$cn_window
	cn_number "${CONTEXT_NUDGE_COMPACT_WINDOW:-}" 0
	if [ "$cn_value" -gt 0 ] && [ "$cn_value" -lt "$cn_window" ]; then
		cn_compact=$cn_value
	fi
	cn_number "${CONTEXT_NUDGE_REPEAT_MARGIN:-}" 10
	[ "$cn_value" -lt 100 ] || cn_value=10
	cn_repeat=$((cn_compact * (100 - cn_value) / 100))

	cn_level=0
	cn_band 1 "${CONTEXT_NUDGE_BAND1_PERCENT:-}" 40 "${CONTEXT_NUDGE_BAND1_TOKENS:-}" 100000
	cn_band 2 "${CONTEXT_NUDGE_BAND2_PERCENT:-}" 60 "${CONTEXT_NUDGE_BAND2_TOKENS:-}" 200000
	cn_band 3 "${CONTEXT_NUDGE_BAND3_PERCENT:-}" 80 "${CONTEXT_NUDGE_BAND3_TOKENS:-}" 300000
	[ "$cn_used" -lt "$cn_repeat" ] || cn_level=4

	case "$cn_level" in
	0) cn_label_text=${CONTEXT_NUDGE_LABEL_OK:-ok} ;;
	1) cn_label_text=${CONTEXT_NUDGE_LABEL_BAND1:-filling} ;;
	2) cn_label_text=${CONTEXT_NUDGE_LABEL_BAND2:-high} ;;
	3) cn_label_text=${CONTEXT_NUDGE_LABEL_BAND3:-very high} ;;
	*) cn_label_text=${CONTEXT_NUDGE_LABEL_CRITICAL:-critical} ;;
	esac
	return 0
}

# cn_band <number> <percent setting> <default> <tokens setting> <default>:
# raises $cn_level to the band's number when the band is reached. A setting of
# 0 turns that trigger off; both at 0 turn the band off.
cn_band() {
	cn_number "$2" "$3"
	cn_band_pct=$cn_value
	cn_number "$4" "$5"
	cn_band_tokens=$cn_value

	# Where the band sits, in tokens: the lower of its two triggers.
	cn_point=''
	[ "$cn_band_pct" -eq 0 ] || cn_point=$((cn_band_pct * cn_window / 100))
	if [ "$cn_band_tokens" -gt 0 ]; then
		if [ -z "$cn_point" ] || [ "$cn_band_tokens" -lt "$cn_point" ]; then
			cn_point=$cn_band_tokens
		fi
	fi
	[ -n "$cn_point" ] && [ "$cn_point" -lt "$cn_repeat" ] || return 0

	# The percentage trigger is tested on the percentage shown, so a notice
	# never comes one rounding step away from the figure it reports.
	if { [ "$cn_band_pct" -gt 0 ] && [ "$cn_shown" -ge "$cn_band_pct" ]; } ||
		{ [ "$cn_band_tokens" -gt 0 ] && [ "$cn_used" -ge "$cn_band_tokens" ]; }; then
		[ "$cn_level" -ge "$1" ] || cn_level=$1
	fi
	return 0
}

# --- usage -------------------------------------------------------------------

# The one place the percentage is worked out. It reads the status-line JSON
# and prints five lines: session id, percentage, tokens, window size, model
# name; "-" stands for a value that is not known.
#
# The percentage is context_window.used_percentage when Claude Code reports
# it; the field is read by that full path, because rate_limits holds other
# fields with the same name, and null means not known. Otherwise it is context_window.total_input_tokens over
# context_window.context_window_size, the same input-only count the reported
# percentage is documented to use.
# The jq program is literal text; nothing in it is for the shell to expand.
# shellcheck disable=SC2016
cn_usage_filter='
def num: if type == "number" and . >= 0 then floor else null end;
def text: if type == "string" then gsub("[\n\r]"; " ") else "" end;
(.context_window | if type == "object" then . else {} end) as $c
| ($c.context_window_size | num) as $size
| ($c.total_input_tokens | num) as $tokens
| ($c.used_percentage | num) as $reported
| (if $reported != null then $reported
   elif $tokens != null and $size != null and $size > 0 then ($tokens * 100 / $size | floor)
   else null end) as $pct
| [(.session_id | text), $pct, $tokens, $size, (.model.display_name? | text)]
| .[] | if . == null or . == "" then "-" else tostring end'

# cn_parse_usage <status-line JSON>: sets $cn_sid, $cn_pct, $cn_tokens,
# $cn_size and $cn_model; each is empty when not known.
cn_parse_usage() {
	cn_sid=''
	cn_pct=''
	cn_tokens=''
	cn_size=''
	cn_model=''
	cn_fields=$(printf '%s' "$1" | "$cn_jq" -r "$cn_usage_filter" 2>/dev/null) || return 1
	{
		IFS= read -r cn_sid
		IFS= read -r cn_pct
		IFS= read -r cn_tokens
		IFS= read -r cn_size
		IFS= read -r cn_model
	} <<EOF
$cn_fields
EOF
	[ "$cn_sid" != - ] || cn_sid=''
	[ "$cn_model" != - ] || cn_model=''
	cn_is_uint "$cn_pct" || cn_pct=''
	cn_is_uint "$cn_tokens" || cn_tokens=''
	cn_is_uint "$cn_size" || cn_size=''
}

# cn_record <status-line JSON>: parses it and writes the session's usage where
# the prompt hook reads it. Never prints; every failure is swallowed, so a
# status line built on this cannot break.
cn_record() {
	cn_parse_usage "$1" || return 0
	cn_safe_id "$cn_sid" || return 0
	[ -n "$cn_dir" ] || return 0
	mkdir -p "$cn_dir" 2>/dev/null || return 0
	cn_tmp="$cn_dir/$cn_sid.$$.tmp"
	# Written whole and then renamed: Claude Code cancels a status-line run
	# that is still going when the next one starts.
	# The time is kept in the file because reading a file's age is not portable.
	if printf '%s %s %s %s\n' "${cn_pct:--}" "${cn_tokens:--}" "${cn_size:--}" "$(date +%s)" \
		>"$cn_tmp" 2>/dev/null; then
		mv -f "$cn_tmp" "$cn_dir/$cn_sid.usage" 2>/dev/null || rm -f "$cn_tmp" 2>/dev/null
	fi
	return 0
}

# cn_read_cache <session id> <now, in epoch seconds>: sets $cn_pct, $cn_tokens
# and $cn_size from the file cn_record wrote. Fails when there is no file, the
# file holds no usage, or it was written more than
# CONTEXT_NUDGE_MAX_AGE seconds ago (0 turns the age check off): a figure that
# old may no longer be true, and no figure is better than a wrong one.
cn_read_cache() {
	cn_pct=''
	cn_tokens=''
	cn_size=''
	[ -n "$cn_dir" ] && [ -r "$cn_dir/$1.usage" ] || return 1
	read -r cn_pct cn_tokens cn_size cn_written <"$cn_dir/$1.usage" || :
	cn_number "${CONTEXT_NUDGE_MAX_AGE:-}" 3600
	if [ "$cn_value" -gt 0 ]; then
		cn_is_uint "${cn_written:-}" && cn_is_uint "${2:-}" || return 1
		[ $(($2 - cn_written)) -le "$cn_value" ] || return 1
	fi
	cn_is_uint "$cn_pct" || cn_pct=''
	cn_is_uint "$cn_tokens" || cn_tokens=''
	cn_is_uint "$cn_size" || cn_size=''
	[ -n "$cn_pct" ] || [ -n "$cn_tokens" ]
}
