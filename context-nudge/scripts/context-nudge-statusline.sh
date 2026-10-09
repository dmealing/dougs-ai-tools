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

model=${cn_model:-Claude}
if ! cn_assess; then
	# No usage yet, or no window size to measure it against.
	printf '%s | context --\n' "$model"
	exit 0
fi

if [ -n "${NO_COLOR:-}" ]; then
	printf '%s | %s%% context | %s\n' "$model" "$cn_shown" "$cn_label_text"
	exit 0
fi

case "$cn_level" in
0) colour=32 ;;
1) colour=33 ;;
*) colour=31 ;;
esac
printf '%s | \033[%sm%s%% context\033[0m | \033[1;%sm%s\033[0m\n' \
	"$model" "$colour" "$cn_shown" "$colour" "$cn_label_text"
