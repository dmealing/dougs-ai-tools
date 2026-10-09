#!/bin/sh
# Cache writer for an existing status line.
#
# Reads the status-line JSON on stdin, records the session's context usage for
# the prompt hook, and writes its input to stdout unchanged. Put it in front of
# the status line you already have:
#
#   sh /path/to/context-nudge-cache.sh | your-status-line-command
#
# or, inside your own script, read the input through it:
#
#   input=$(sh /path/to/context-nudge-cache.sh)
#
# It prints nothing of its own and never fails: without jq it only passes the
# input through.

set -u

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)
# shellcheck source=/dev/null
. "$here/context-nudge-lib.sh"

# The trailing x keeps the newlines that $(...) would strip.
input=$(
	cat
	printf x
)
input=${input%x}

if cn_have_jq; then
	cn_record "$input"
fi
printf '%s' "$input"
