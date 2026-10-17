#!/bin/sh
# Tests for ../skills/challenge/challenge-log.sh. Every case uses a throwaway
# record store and a throwaway git repository.
#
# Run: sh challenge/tests/test-log.sh

# The variables come from the sourced fixture; the single quotes hold code that
# holds() evaluates.
# shellcheck disable=SC2016,SC2154

set -u

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)
root=$(dirname -- "$here")
repo=$(dirname -- "$root")

# shellcheck source=/dev/null
. "$repo/lib/test-helpers.sh"
# shellcheck source=/dev/null
. "$here/fixture.sh"

# log_cmd <args...>: runs challenge-log.sh; sets $status, $work/out, $work/err.
log_cmd() {
	status=0
	sh "$log_sh" "$@" >"$work/out" 2>"$work/err" || status=$?
}
out_has() { grep -qF -- "$1" "$work/out"; }
err_has() { grep -qF -- "$1" "$work/err"; }

# answered <slug> [flags...]: a record with both answers, as a finished run leaves it.
answered() {
	new_record "$@"
	printf 'An answer long enough to count.\n' >"$rec/A.md"
	printf 'Another answer long enough to count.\n' >"$rec/B.md"
	printf 'A_session=s1\nB_session=s2\ncost_usd=3.0000\nsynth_cost_usd=0.5000\n' >"$rec/.arms"
	write_brief "$rec/brief.md"
}

# --- new ----------------------------------------------------------------------------
log_cmd new first "$target"
rec="$CHALLENGE_HOME/first"
check "new succeeds in a git repository" [ "$status" -eq 0 ]
check "new prints the record folder" [ "$(cat "$work/out")" = "$rec" ]
check "new does not print the A/B assignment" [ -z "$(grep -E 'opus|fable|A=|B=' "$work/out")" ]
check "new pins the commit" grep -q "^commit=$(git -C "$target" rev-parse HEAD)" "$rec/.meta"
check "new states the cost" err_has "plan quota"
check "the default pair is Opus 5.5 with Opus 5" holds '[ "$(sed -n "s/^[AB]=//p" "$rec/.map" | sort | paste -sd+ -)" = "claude-opus-5+claude-opus-5-5" ]'
check "the template has no <fill in> placeholder" holds '! grep -qiF "<fill in>" "$rec/brief.md"'
check "the template does not carry an absolute path" holds '! grep -qE "/(home|Users)/" "$rec/brief.md"'

log_cmd new first "$target"
check "new will not overwrite a record" [ "$status" -eq 2 ]

log_cmd new twin "$target" --twin
check "--twin puts one model in both arms" holds '[ "$(sed -n "s/^A=//p" "$CHALLENGE_HOME/twin/.map")" = "$(sed -n "s/^B=//p" "$CHALLENGE_HOME/twin/.map")" ]'

log_cmd new fable-default "$target" --fable
check "--fable puts Fable 5.1 in the pair" holds 'grep -q "claude-fable-5-1" "$CHALLENGE_HOME/fable-default/.map"'
check "--fable records the opt-in" holds 'grep -qx "fable_optin=yes" "$CHALLENGE_HOME/fable-default/.meta"'
check "--fable warns about usage credits" err_has "usage credits"
check "a record made without --fable records that" holds 'grep -qx "fable_optin=no" "$rec/.meta"'

status=0
CHALLENGE_MODEL_A=claude-fable-5-1 sh "$log_sh" new fable-env "$target" >/dev/null 2>&1 || status=$?
check "a Fable model from the environment still needs --fable" [ "$status" -eq 2 ]

status=0
CHALLENGE_MODEL_A=gpt-9 sh "$log_sh" new not-claude "$target" >/dev/null 2>"$work/err" || status=$?
check "a model that is not a Claude model is refused at once" holds '[ "$status" -eq 2 ] && err_has "not a Claude model"'
check "a refused record leaves no folder behind" [ ! -e "$CHALLENGE_HOME/not-claude" ]

status=0
CHALLENGE_MODEL_A=opus CHALLENGE_MODEL_B=claude-opus-5 sh "$log_sh" new overlap "$target" >/dev/null 2>"$work/err" || status=$?
check "an alias and a model of its family are refused as one pair" holds '[ "$status" -eq 2 ] && err_has "same model"'

status=0
CHALLENGE_MODEL_A=opus CHALLENGE_MODEL_B=sonnet sh "$log_sh" new aliases "$target" >/dev/null 2>&1 || status=$?
check "two aliases of different families are accepted" [ "$status" -eq 0 ]

status=0
CHALLENGE_MODEL_A=claude-opus-5-20261001 CHALLENGE_MODEL_B=claude-opus-5-5 sh "$log_sh" new dated "$target" >/dev/null 2>&1 || status=$?
check "a dated ID is accepted and does not collide with the next generation" [ "$status" -eq 0 ]

log_cmd new nogit "$work"
check "new refuses a folder that is not a git repository" [ "$status" -eq 2 ]

log_cmd new '../up' "$target"
check "new refuses a slug that climbs out" [ "$status" -eq 2 ]
log_cmd new '.hidden' "$target"
check "new refuses a slug that starts with a dot" [ "$status" -eq 2 ]
log_cmd new needs-repo
check "new needs a repository" [ "$status" -eq 2 ]

# --- note --------------------------------------------------------------------------------
log_cmd note first --stakes high --agreed no
check "note refuses a record with no answers" [ "$status" -eq 2 ]

answered r-yes
log_cmd note r-yes --stakes high --agreed yes --note 'same call'
check "note records a row" holds '[ "$status" -eq 0 ] && out_has "agreed=yes"'
check "the row carries no model assignment in what note printed" holds '! grep -q "A=" "$work/out"'
log_cmd note r-yes --agreed yes
check "note requires --stakes" [ "$status" -eq 2 ]
log_cmd note r-yes --stakes high
check "note requires --agreed" [ "$status" -eq 2 ]
log_cmd note r-yes --stakes high --agreed maybe
check "note refuses an agreement it does not know" [ "$status" -eq 2 ]
log_cmd note r-yes --stakes medium --agreed yes
check "note refuses stakes it does not know" [ "$status" -eq 2 ]
log_cmd note r-yes --stakes
check "note refuses a flag with no value" [ "$status" -eq 2 ]
log_cmd note r-yes --pick A
check "note refuses the retired --pick" [ "$status" -eq 2 ]

check "the row is valid JSON with the costs" holds 'python3 -c "import json,sys; r=[json.loads(l) for l in open(sys.argv[1])][0]; assert r[\"cost_usd\"]==\"3.0000\" and r[\"synth_cost_usd\"]==\"0.5000\" and len(r[\"brief_sha\"])==16" "$CHALLENGE_HOME/challenges.jsonl"'

# --- status: partial is a split -----------------------------------------------------------
rm -f "$CHALLENGE_HOME/challenges.jsonl"
answered s-partial
log_cmd note s-partial --stakes high --agreed partial
log_cmd status
check "a lone partial row is counted as a split" out_has "1/1"
check "status shows the partial column" out_has "1 partial"
check "status shows an interval" out_has "95% interval"
check "status marks a small n as directional" out_has "directional only"

answered s-yes
log_cmd note s-yes --stakes high --agreed yes
answered s-no
log_cmd note s-no --stakes high --agreed no
answered s-low
log_cmd note s-low --stakes low --agreed no
log_cmd status
check "yes, partial and no make two splits in three rows" out_has "2/3"
check "a low-stakes row is not in the rate" out_has "(1 no, 1 partial)"

# --- status: the interval ---------------------------------------------------------------------
rm -f "$CHALLENGE_HOME/challenges.jsonl"
i=1
while [ "$i" -le 6 ]; do
	answered "twin-$i" --twin
	log_cmd note "twin-$i" --stakes high --agreed yes
	i=$((i + 1))
done
log_cmd status
check "0 splits in 6 rows still allows a true rate near 39 percent" out_has "0/6"
check "...and says so" out_has "0-39%"

# --- void and list ---------------------------------------------------------------------------
log_cmd void twin-1 'bad brief'
check "void marks a row" [ "$status" -eq 0 ]
log_cmd status
check "a voided row leaves the tally" out_has "0/5"
log_cmd void twin-1 'again'
check "void will not void the same row twice" [ "$status" -ne 0 ]
log_cmd void twin-2
check "void needs a reason" [ "$status" -eq 2 ]
log_cmd list 3
check "list shows recent rows" out_has "twin-6"
log_cmd list zero
check "list refuses a non-number" [ "$status" -eq 2 ]
log_cmd nonsense
check "an unknown command is refused" [ "$status" -eq 2 ]

finish log
