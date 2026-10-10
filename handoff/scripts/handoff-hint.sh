#!/bin/sh
# SessionStart hook: when live handoffs exist for this project, print a
# message to the user that names them and says how to resume. Nothing from
# inside a handoff is read, and nothing goes to the model: the output is a
# systemMessage, which Claude Code shows to the user only.
#
# Silent when there are no live handoffs, when HANDOFF_HINT=off, and on any
# error. It lists one folder and reads no file.
#
# Settings:
#   HANDOFF_HINT=off   turn the message off (0, no and false work too)
#   HANDOFF_DIR        the store, as the handoff skill defines it

# The store rule and the project rule are copied from the handoff skill and
# checked against it by the tests.
# shellcheck disable=SC2016

exec 2>/dev/null

case "${HANDOFF_HINT:-}" in off | OFF | 0 | no | false) exit 0 ;; esac

main=$(git worktree list --porcelain 2>/dev/null | sed -n '1s/^worktree //p')
bare=$(git worktree list --porcelain 2>/dev/null | sed -n '2s/^bare$/yes/p')
project=$(basename "${main:-$PWD}")
if [ -n "$bare" ]; then case "$project" in .bare | .git) project=$(basename "$(dirname "$main")") ;; *.git) project=${project%.git} ;; esac; fi
root="${HANDOFF_DIR:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/handoffs}"
dir="$root/$project"

count=0
names=''
first=''
for file in "$dir"/*.md; do
	[ -f "$file" ] || continue
	count=$((count + 1))
	stream=$(basename "$file" .md)
	[ -n "$first" ] || first=$stream
	[ "$count" -gt 5 ] || names="${names:+$names, }$stream"
done
[ "$count" -gt 0 ] || exit 0

if [ "$count" -eq 1 ]; then
	head_line="1 live handoff for $project: $names."
else
	head_line="$count live handoffs for $project: $names"
	[ "$count" -le 5 ] && head_line="$head_line."
	[ "$count" -le 5 ] || head_line="$head_line, and $((count - 5)) more."
fi
message="$head_line Resume with /pickup if installed, or ask Claude to read $dir/$first.md. Turn this message off with HANDOFF_HINT=off."

# The message holds a path and file names, so quote them for JSON.
escaped=$(printf '%s' "$message" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr '\n\t' '  ')
printf '{"systemMessage":"%s"}\n' "$escaped"
exit 0
