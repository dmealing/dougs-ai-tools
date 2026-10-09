#!/bin/sh
# A complete, minimal status line: model name, context percentage, band label.
#
#   Opus | 42% context | filling
#
# It also records the session's context usage for the prompt hook, exactly as
# context-nudge-cache.sh does. Use this one when you have no status line of
# your own; use the cache writer when you do.
#
# Colour is on unless NO_COLOR is set.

# The cn_ names come from the sourced context-nudge-lib.sh.
# shellcheck disable=SC2154

set -u

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)
# shellcheck source=/dev/null
. "$here/context-nudge-lib.sh"

input=$(cat)

if ! cn_have_jq; then
	printf 'context-nudge: jq not found; install jq to see context usage\n'
	exit 0
fi

cn_record "$input"
cn_load_settings

model=${cn_model:-Claude}
if [ -z "$cn_pct" ]; then
	printf '%s | context --\n' "$model"
	exit 0
fi

cn_label "$cn_pct"
if [ -n "${NO_COLOR:-}" ]; then
	printf '%s | %s%% context | %s\n' "$model" "$cn_pct" "$cn_label_text"
	exit 0
fi

if [ "$cn_pct" -ge "$cn_high" ]; then
	colour=31
elif [ "$cn_pct" -ge "$cn_first" ]; then
	colour=33
else
	colour=32
fi
printf '%s | \033[%sm%s%% context\033[0m | \033[1;%sm%s\033[0m\n' \
	"$model" "$colour" "$cn_pct" "$colour" "$cn_label_text"
