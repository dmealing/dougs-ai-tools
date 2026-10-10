#!/bin/sh
# Tests for the SessionStart hint (scripts/handoff-hint.sh) in scratch
# directories: what it prints, when it stays silent, and that it never
# repeats a handoff's contents.
#
# Run: sh handoff/tests/test-hint.sh

# $store_rule and $project_rule come from the sourced shipped-file-checks.sh.
# shellcheck disable=SC2154

set -u

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)
root=$(dirname -- "$here")
repo=$(dirname -- "$root")
hint="$root/scripts/handoff-hint.sh"

# shellcheck source=/dev/null
. "$repo/lib/test-helpers.sh"
# shellcheck source=/dev/null
. "$repo/lib/shipped-file-checks.sh"

work=$(mktemp -d "${TMPDIR:-/tmp}/handoff-hint-test.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT INT TERM

store="$work/store"
mkdir -p "$work/parcel-tracker" "$store/parcel-tracker/done" "$store/empty-project" "$work/empty-project"

# contains <text> <fragment>: the text includes the fragment.
contains() { printf '%s\n' "$1" | grep -qF -- "$2"; }

# run_hint <directory>: the hint's output when the session starts there.
run_hint() {
	(cd "$1" && env -u HANDOFF_HINT -u CLAUDE_CONFIG_DIR HANDOFF_DIR="$store" GIT_CEILING_DIRECTORIES="$work" sh "$hint" </dev/null 2>&1)
}

# --- silent with nothing live ---------------------------------------------------
out=$(run_hint "$work/empty-project")
check "prints nothing when the project has no handoffs" [ -z "$out" ]
out=$(run_hint "$work")
check "prints nothing when the project has no folder in the store" [ -z "$out" ]
printf 'x\n' >"$store/parcel-tracker/done/old-work.md"
out=$(run_hint "$work/parcel-tracker")
check "archived handoffs do not count" [ -z "$out" ]

# --- one live handoff -----------------------------------------------------------
printf 'SECRET-BODY-LINE\n' >"$store/parcel-tracker/fix-retry.md"
out=$(run_hint "$work/parcel-tracker")
case "$out" in '{"systemMessage":"'*'"}') pass "prints one systemMessage object" ;; *) fail "output is not a systemMessage object: $out" ;; esac
check "the message says there is 1 live handoff" contains "$out" "1 live handoff for parcel-tracker: fix-retry."
check "the message names how to resume" contains "$out" "/pickup"
check "the message names the file" contains "$out" "parcel-tracker/fix-retry.md"
check "the message names the setting that turns it off" contains "$out" "HANDOFF_HINT=off"
check "the output is one line" [ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" -eq 1 ]
no_contents() { ! printf '%s\n' "$out" | grep -qF 'SECRET-BODY-LINE'; }
check "nothing from inside the handoff is printed" no_contents
no_model_context() { ! printf '%s\n' "$out" | grep -qF 'additionalContext'; }
check "nothing is added to the model's context" no_model_context

# --- several, and a long list ---------------------------------------------------
printf 'x\n' >"$store/parcel-tracker/search-index.md"
out=$(run_hint "$work/parcel-tracker")
check "the message counts two and names both" contains "$out" "2 live handoffs for parcel-tracker: fix-retry, search-index."
for n in 3 4 5 6 7; do printf 'x\n' >"$store/parcel-tracker/stream-$n.md"; done
out=$(run_hint "$work/parcel-tracker")
check "a long list is cut and counted" contains "$out" "7 live handoffs for parcel-tracker: fix-retry, search-index, stream-3, stream-4, stream-5, and 2 more."

# --- the project is found as the skill finds it ---------------------------------
if command -v git >/dev/null 2>&1; then
	mkdir -p "$work/parcel-tracker-checkout"
	(
		cd "$work/parcel-tracker-checkout" && git init -q . &&
			git -c user.name=test -c user.email=test@example.invalid commit -q --allow-empty -m init &&
			git worktree add -q "$work/parcel-tracker-side" -b side
	) >/dev/null 2>&1
	mkdir -p "$store/parcel-tracker-checkout"
	printf 'x\n' >"$store/parcel-tracker-checkout/side-work.md"
	out=$(run_hint "$work/parcel-tracker-side")
	check "a second worktree finds the main working tree's folder" contains "$out" "1 live handoff for parcel-tracker-checkout: side-work."
else
	printf 'skip - git not found; worktree lookup not exercised\n'
fi

# --- the switch -----------------------------------------------------------------
for value in off 0 no false; do
	out=$(cd "$work/parcel-tracker" && HANDOFF_HINT=$value HANDOFF_DIR="$store" sh "$hint" </dev/null 2>&1)
	check "HANDOFF_HINT=$value turns it off" [ -z "$out" ]
done

# --- failure is silent ----------------------------------------------------------
out=$(cd "$work/parcel-tracker" && HANDOFF_DIR="$work/no/such/store" sh "$hint" </dev/null 2>&1)
check "a missing store prints nothing" [ -z "$out" ]
status=$(cd "$work/parcel-tracker" && HANDOFF_DIR="$work/no/such/store" sh "$hint" </dev/null >/dev/null 2>&1; echo $?)
check "a missing store exits 0" [ "$status" -eq 0 ]

# --- the rules are the skill's ---------------------------------------------------
if rule_in_file "$project_rule" "$hint"; then pass "the hint uses the skill's project rule"; else fail "the hint's project rule differs from the skill's"; fi
check "the hint uses the skill's store rule" grep -qxF "$store_rule" "$hint"

# --- wiring -----------------------------------------------------------------------
check_posix_shell "$hint"
check_portable_shell "$hint"
if python3 -c 'import json' >/dev/null 2>&1; then
	check "hooks.json names the SessionStart event" [ "$(json_value "$root/hooks/hooks.json" hooks SessionStart 2>/dev/null | grep -c handoff-hint.sh)" -ge 1 ]
	check "hooks.json registers the script" grep -qF 'scripts/handoff-hint.sh' "$root/hooks/hooks.json"
fi
check "the script named in hooks.json ships" [ -f "$root/scripts/handoff-hint.sh" ]
check "the README documents HANDOFF_HINT" grep -qF 'HANDOFF_HINT' "$root/README.md"

finish hint
