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

cn_dir="${CLAUDE_CONFIG_DIR:-${HOME:-}/.claude}/context-nudge"
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

# cn_safe_id <session id>: usable as a file name, with no path in it.
cn_safe_id() {
	case "${1:-}" in '' | .* | *[!A-Za-z0-9._-]*) return 1 ;; esac
}

# --- settings ----------------------------------------------------------------

# cn_load_settings: reads the environment into $cn_bands (ascending is not
# required), $cn_first, $cn_high and $cn_repeat. Bands at or above the
# every-prompt threshold are dropped: that threshold is the last band.
cn_load_settings() {
	cn_number "${CONTEXT_NUDGE_REPEAT_AT:-}" 90
	cn_repeat=$cn_value
	cn_number "${CONTEXT_NUDGE_HIGH_AT:-}" 70
	cn_high=$cn_value
	cn_parse_bands "${CONTEXT_NUDGE_BANDS:-}"
	[ -n "$cn_bands" ] || cn_parse_bands '40 50 60 70 80 85'
	# Every default band is at or above the threshold: it is then the only band.
	[ -n "$cn_bands" ] || cn_first=$cn_repeat
}

# cn_parse_bands <list separated by spaces or commas>
cn_parse_bands() {
	cn_bands=''
	cn_first=''
	cn_old_ifs=$IFS
	IFS=' ,'
	set -f
	# Splitting the list into words is the point.
	# shellcheck disable=SC2086
	set -- $1
	set +f
	IFS=$cn_old_ifs
	for cn_item in "$@"; do
		cn_is_uint "$cn_item" || continue
		cn_number "$cn_item" 0
		[ "$cn_value" -gt 0 ] && [ "$cn_value" -lt "$cn_repeat" ] || continue
		cn_bands="$cn_bands $cn_value"
		if [ -z "$cn_first" ] || [ "$cn_value" -lt "$cn_first" ]; then
			cn_first=$cn_value
		fi
	done
}

# cn_label <percentage>: sets $cn_label_text to the word for that percentage.
# Call cn_load_settings first.
cn_label() {
	if [ "$1" -ge "$cn_repeat" ]; then
		cn_label_text=${CONTEXT_NUDGE_LABEL_CRITICAL:-critical}
	elif [ "$1" -ge "$cn_high" ]; then
		cn_label_text=${CONTEXT_NUDGE_LABEL_HIGH:-high}
	elif [ "$1" -ge "$cn_first" ]; then
		cn_label_text=${CONTEXT_NUDGE_LABEL_FILLING:-filling}
	else
		cn_label_text=${CONTEXT_NUDGE_LABEL_OK:-ok}
	fi
}

# --- usage -------------------------------------------------------------------

# The one place the percentage is worked out. It reads the status-line JSON
# and prints five lines: session id, percentage, tokens, window size, model
# name; "-" stands for a value that is not known.
#
# The percentage is context_window.used_percentage when Claude Code reports
# it. Otherwise it is context_window.total_input_tokens over
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
	mkdir -p "$cn_dir" 2>/dev/null || return 0
	cn_tmp="$cn_dir/$cn_sid.$$.tmp"
	# Written whole and then renamed: Claude Code cancels a status-line run
	# that is still going when the next one starts.
	if printf '%s %s %s\n' "${cn_pct:--}" "${cn_tokens:--}" "${cn_size:--}" >"$cn_tmp" 2>/dev/null; then
		mv -f "$cn_tmp" "$cn_dir/$cn_sid.usage" 2>/dev/null || rm -f "$cn_tmp" 2>/dev/null
	fi
	return 0
}

# cn_read_cache <session id>: sets $cn_pct, $cn_tokens and $cn_size from the
# file cn_record wrote. Fails when there is no file.
cn_read_cache() {
	cn_pct=''
	cn_tokens=''
	cn_size=''
	[ -r "$cn_dir/$1.usage" ] || return 1
	read -r cn_pct cn_tokens cn_size <"$cn_dir/$1.usage" || :
	cn_is_uint "$cn_pct" || cn_pct=''
	cn_is_uint "$cn_tokens" || cn_tokens=''
	cn_is_uint "$cn_size" || cn_size=''
	return 0
}
