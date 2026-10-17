#!/bin/sh
# Tests for ../skills/challenge/challenge-run.sh, against a stub claude. No
# model is called: the stub records its calls and prints canned JSON.
#
# Run: sh challenge/tests/test-runner.sh

# The variables come from the sourced fixture; the single quotes hold code that
# holds() evaluates.
# shellcheck disable=SC2016,SC2154,SC2086

set -u

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)
root=$(dirname -- "$here")
repo=$(dirname -- "$root")

# shellcheck source=/dev/null
. "$repo/lib/test-helpers.sh"
# shellcheck source=/dev/null
. "$here/fixture.sh"

err_has() { grep -qiF -- "$1" "$work/err"; }
out_has() { grep -qF -- "$1" "$work/out"; }

# --- the brief guards (an unfilled template used to pass them all) ---------------
new_record template
run_runner template
check "an untouched template is refused" [ "$status" -eq 2 ]
check "the refusal names the empty section" err_has "no text under"
check "an untouched template starts no model" [ "$(calls)" -eq 0 ]

new_record placeholder
write_brief "$rec/brief.md"
printf '\nRepo root: <fill in>\n' >>"$rec/brief.md"
run_runner placeholder
check "a <fill in> placeholder is refused" [ "$status" -eq 2 ]
check "a <fill in> placeholder starts no model" [ "$(calls)" -eq 0 ]

new_record task-placeholder
write_brief "$rec/brief.md"
printf '\n{TASK}\n' >>"$rec/brief.md"
run_runner task-placeholder
check "a {TASK} placeholder is refused" [ "$status" -eq 2 ]

new_record short
printf '# Question\n\nToo short.\n' >"$rec/brief.md"
run_runner short
check "a tiny brief is refused" [ "$status" -eq 2 ]

new_record no-scope
write_brief "$rec/brief.md"
python3 - "$rec/brief.md" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
start = s.index("I read src/cache.py")
end = s.index("# The strongest case")
s = s[:start] + "I read src/cache.py and src/server.py in full, and both agree with each other.\n\n" + s[end:]
open(p, "w").write(s)
PY
run_runner no-scope
check "a Facts section with no scope is refused, though its heading says VERIFICATION SCOPE" [ "$status" -eq 2 ]
check "the scope refusal says so" err_has "verification scope"
check "a missing scope starts no model" [ "$(calls)" -eq 0 ]

run_with 'CHALLENGE_SKIP_SCOPE_CHECK=1' no-scope --arms-only
check "CHALLENGE_SKIP_SCOPE_CHECK=1 allows a brief with no scope" [ "$status" -eq 0 ]
reset_stub

# --- a normal run -------------------------------------------------------------------
ready_record normal
run_runner normal
check "a filled brief runs to the end" [ "$status" -eq 0 ]
check "both answers are written" holds '[ -s "$rec/A.md" ] && [ -s "$rec/B.md" ]'
check "the differential is written" [ -s "$rec/differential.md" ]
check "two arms and two differential passes ran" holds '[ "$(calls_of arm)" -eq 2 ] && [ "$(calls_of synth)" -eq 2 ]'
check "the run reports the agreement" out_has "agreement: yes"
check "the run states the cost before it dispatches" err_has "plan quota"

arm_calls=$(grep -l '^--add-dir$' "$STUB_DIR"/args.*)
arm_args=$(printf '%s\n' $arm_calls | head -n 1)
check "the arms run in the clean room" holds '[ -n "$arm_calls" ] && [ -z "$(grep -L '\''^--safe-mode$'\'' $arm_calls)" ]'
n_identical=0
for call_args in $arm_calls; do
	call_id=${call_args##*args.}
	if cmp -s "$STUB_DIR/stdin.$call_id" "$rec/brief.md"; then n_identical=$((n_identical + 1)); fi
done
check "both arms received the brief, byte for byte, on standard input" [ "$n_identical" -eq 2 ]
check "the brief is not on the command line" [ -z "$(grep -l 'legacy cache' $arm_calls 2>/dev/null)" ]
check "the default pair is Opus 5.5 with Opus 5" holds '[ "$(grep -c '\''^arm|claude-opus-5-5|'\'' "$STUB_DIR/calls.log")" -eq 1 ] && [ "$(grep -c '\''^arm|claude-opus-5|'\'' "$STUB_DIR/calls.log")" -eq 1 ]'
check "the default cap is 8 dollars" grep -qx '8' "$arm_args"
n_tool_sets=0
for call_args in $arm_calls; do
	call_tools=$(awk 'on && /^--/ { exit } on { printf "%s ", $0 } $0 == "--tools" { on = 1 }' "$call_args")
	if [ "$call_tools" = "Read Grep Glob Bash " ]; then n_tool_sets=$((n_tool_sets + 1)); fi
done
check "both arms have exactly Read, Grep, Glob and Bash, and no Write, Edit or Agent" [ "$n_tool_sets" -eq 2 ]
check "an arm runs in the repository it was given" grep -qx "$target" "${arm_args%args.*}cwd.${arm_args##*args.}"
check "no arm names the repository path on its command line" [ "$(grep -c "$target" "$arm_args")" -eq 1 ]

check "the differential runs on the default outside model" grep -q '^synth|claude-sonnet-5-5|' "$STUB_DIR/calls.log"
check "the differential has no tools" grep -q '^synth|[^|]*|1|$' "$STUB_DIR/calls.log"
synth_prompts=$(grep -l '<<<ANSWER 1>>>' "$STUB_DIR"/stdin.*)
check "no differential prompt names a model or a provider" [ -z "$(grep -il 'opus\|claude\|fable\|anthropic' $synth_prompts)" ]
first_marks=''
for prompt in $synth_prompts; do
	first_marks="$first_marks $(sed -n '/<<<ANSWER 1>>>/,/<<<END ANSWER 1>>>/p' "$prompt" | grep -o 'MARK[XY]' | head -n 1)"
done
check "the two differential passes read the answers in opposite orders" holds '[ "$first_marks" = " MARKX MARKY" ] || [ "$first_marks" = " MARKY MARKX" ]'
synth_dir=$(head -n 1 "$(grep -l '<<<ANSWER 1>>>' "$STUB_DIR"/stdin.* | head -n 1 | sed 's/stdin\./cwd./')")
check "the differential does not run in the repository" [ "$synth_dir" != "$target" ]
check "the arms' cost and the differential's are both recorded" holds 'grep -q '\''^cost_usd=3.0000$'\'' "$rec/.arms" && grep -q '\''^synth_cost_usd=3.0000$'\'' "$rec/.arms"'
check "the record does not say which arm was which in anything the run printed" [ -z "$(grep -l 'opus-5' "$work/out")" ]
check "the pairing is printed" err_has "pairing: claude-opus-5+claude-opus-5-5"

# --- the differential: passes that disagree --------------------------------------------
reset_stub
ready_record order-effect
run_with 'STUB_AGREE_X_FIRST=yes STUB_AGREE_Y_FIRST=no' order-effect
check "passes that disagree give partial, not agreement" out_has "agreement: partial"
check "the differential file says the verdict depended on the order" grep -q 'DISAGREE' "$rec/differential.md"

reset_stub
ready_record both-no
run_with 'STUB_AGREE_X_FIRST=no' both-no
check "passes that agree on no give no" out_has "agreement: no"

# --- the differential: failures --------------------------------------------------------
reset_stub
ready_record synth-fails
run_with 'STUB_SYNTH_FAIL=1' synth-fails
check "a failed differential exits 4" [ "$status" -eq 4 ]
check "the arms' answers survive a failed differential" holds '[ -s "$rec/A.md" ] && [ -s "$rec/B.md" ]'
check "a failed differential leaves no differential file" [ ! -e "$rec/differential.md" ]
before=$(calls_of arm)
run_runner synth-fails --differential
check "--differential writes it without running the arms again" holds '[ "$status" -eq 0 ] && [ -s "$rec/differential.md" ] && [ "$(calls_of arm)" -eq "$before" ]'

reset_stub
ready_record one-pass
run_with 'STUB_SYNTH_FAIL_PASS=2' one-pass
check "one differential pass failing still gives a differential" holds '[ "$status" -eq 0 ] && [ -s "$rec/differential.md" ]'
check "the differential says the order effect is unchecked" grep -q 'unchecked' "$rec/differential.md"

reset_stub
ready_record bad-format
run_with 'STUB_SYNTH_BAD=1' bad-format
check "a differential with no AGREEMENT line is rejected" [ "$status" -eq 4 ]

reset_stub
ready_record arms-only
run_runner arms-only --arms-only
check "--arms-only starts no differential" holds '[ "$status" -eq 0 ] && [ "$(calls_of synth)" -eq 0 ] && [ ! -e "$rec/differential.md" ]'

# --- models: refused before they are paid for -----------------------------------------
reset_stub
ready_record synth-is-arm
run_with 'CHALLENGE_SYNTH_MODEL=claude-opus-5-5' synth-is-arm
check "a differential model that is an arm is refused" [ "$status" -eq 2 ]
check "...before any model is started" [ "$(calls)" -eq 0 ]
run_with 'CHALLENGE_SYNTH_MODEL=opus' synth-is-arm
check "a differential alias that could be an arm is refused" holds '[ "$status" -eq 2 ] && [ "$(calls)" -eq 0 ]'
run_with 'CHALLENGE_SYNTH_MODEL=not-a-model' synth-is-arm
check "a differential model that is not a Claude model is refused" holds '[ "$status" -eq 2 ] && [ "$(calls)" -eq 0 ]'
run_with 'CHALLENGE_SYNTH_MODEL=claude-fable-5-1' synth-is-arm
check "a Fable differential model is refused" holds '[ "$status" -eq 2 ] && [ "$(calls)" -eq 0 ]'

printf 'A=claude-opus-5-5\nB=claude-fable-5-1\n' >"$rec/.map"
run_runner synth-is-arm
check "a Fable arm in a record made without --fable is refused" holds '[ "$status" -eq 2 ] && [ "$(calls)" -eq 0 ]'

reset_stub
ready_record bad-cap
run_with 'CHALLENGE_ARM_BUDGET_USD=lots' bad-cap
check "a cap that is not a number is refused" holds '[ "$status" -eq 2 ] && [ "$(calls)" -eq 0 ]'

# --- models: aliases and suffixes are accepted --------------------------------------------
reset_stub
ready_with 'CHALLENGE_MODEL_A=opus CHALLENGE_MODEL_B=claude-haiku-5-5' alias
run_with 'STUB_MODE=alias' alias
check "a family alias in the configuration is accepted by the model check" holds '[ "$status" -eq 0 ] && [ -s "$rec/A.md" ] && [ -s "$rec/B.md" ]'

reset_stub
ready_record suffixed
run_with 'STUB_MODE=nocanon' suffixed
check "a [1m]-suffixed model with no canonicalModel is accepted" holds '[ "$status" -eq 0 ] && [ -s "$rec/A.md" ] && [ -s "$rec/B.md" ]'

reset_stub
ready_record mismatch
run_with 'STUB_MODE=mismatch' mismatch
check "a different model answering is refused" [ "$status" -eq 2 ]
check "the refusal reports both arms' failures" err_has "both arms failed"
check "the refusal says the arms were billed" err_has "were billed"
check "the refusal says --reextract re-reads for free" err_has "--reextract"
check "no answer is written when the model is wrong" holds '[ ! -e "$rec/A.md" ] && [ ! -e "$rec/B.md" ]'
check "the raw output is kept" holds '[ -s "$rec/.A.json" ] && [ -s "$rec/.B.json" ]'
before=$(calls)
run_runner mismatch --reextract
check "--reextract starts no model" [ "$(calls)" -eq "$before" ]
check "--reextract still refuses a wrong model" [ "$status" -eq 2 ]

# --- one arm fails: the other's answer is kept -------------------------------------------------
reset_stub
ready_record one-arm
run_with 'STUB_FAIL_MODEL=claude-opus-5' one-arm
check "one arm failing exits 3" [ "$status" -eq 3 ]
check "the surviving arm's answer is kept" holds '[ -s "$rec/A.md" ] || [ -s "$rec/B.md" ]'
check "the budget error is named" err_has "BUDGET EXHAUSTED"
check "no differential is written over one voice" holds '[ "$(calls_of synth)" -eq 0 ] && [ ! -e "$rec/differential.md" ]'
check "the run says this is not a challenge" err_has "NOT a challenge"

# --- Fable is opt-in ---------------------------------------------------------------------------
reset_stub
status=0
CHALLENGE_MODEL_B=claude-fable-5-1 sh "$log_sh" new fable-no "$target" >/dev/null 2>"$work/err" || status=$?
check "a Fable model without --fable is refused" holds '[ "$status" -eq 2 ] && err_has "--fable"'
ready_record fable-yes --fable
check "--fable puts Fable 5.1 in the pair" grep -q 'claude-fable-5-1' "$rec/.map"
run_runner fable-yes
check "a Fable pair runs" [ "$status" -eq 0 ]
check "a Fable pair warns about usage credits" err_has "usage credits"
check "a Fable pair has the higher default cap" grep -qx '16' "$(grep -l '^--add-dir$' "$STUB_DIR"/args.* | head -n 1)"

# --- the repository is watched while the arms run ---------------------------------------------
reset_stub
ready_record dirty
run_with 'STUB_DIRTY=1' dirty --arms-only
check "an arm that writes into the repository is reported" err_has "CHANGED"
check "the change is marked in the record" grep -q '^mutated=yes' "$rec/.meta"
rm -f "$target/stub-wrote.txt"

reset_stub
ready_record clean
run_runner clean --arms-only
check "an arm that writes nothing is not reported" [ -z "$(grep -F 'CHANGED' "$work/err")" ]

# --- the time limit works without timeout(1) -------------------------------------------------
reset_stub
ready_record slow
run_with 'CHALLENGE_ARM_TIMEOUT=1 STUB_SLEEP=6' slow --arms-only
check "an arm past the limit is killed and the run fails" [ "$status" -eq 2 ]
check "the failure says the arm timed out" err_has "timed out after 1s"

# --- a signal stops the run and the calls it started ------------------------------------------
reset_stub
ready_record stopped
STUB_SLEEP=30 sh "$run_sh" stopped >"$work/out" 2>"$work/err" &
runner_pid=$!
waited=0
while [ "$(calls_of arm)" -lt 2 ] && [ "$waited" -lt 20 ]; do
	sleep 1
	waited=$((waited + 1))
done
kill -TERM "$runner_pid"
status=0
wait "$runner_pid" || status=$?
sleep 1
n_alive=0
for call_args in "$STUB_DIR"/args.*; do
	if kill -0 "${call_args##*args.}" 2>/dev/null; then n_alive=$((n_alive + 1)); fi
done
check "a stopped run exits 143" [ "$status" -eq 143 ]
check "a stopped run stops both arms" [ "$n_alive" -eq 0 ]
check "a stopped run starts no differential" [ "$(calls_of synth)" -eq 0 ]

# --- where the records go -----------------------------------------------------------------------
reset_stub
status=0
(
	unset CHALLENGE_HOME
	CLAUDE_CONFIG_DIR="$work/cfg"
	export CLAUDE_CONFIG_DIR
	sh "$log_sh" new in-config "$target" >/dev/null 2>&1
) || status=$?
check "records default to a folder under the Claude configuration directory" holds '[ "$status" -eq 0 ] && [ -f "$work/cfg/challenge-log/in-config/.map" ]'

reset_stub
status=0
sh "$run_sh" '../escape' >/dev/null 2>&1 || status=$?
check "a slug cannot climb out of the record folder" [ "$status" -eq 2 ]

# --- warnings --------------------------------------------------------------------------------------
reset_stub
ready_record leading
printf '\nI think the answer is to remove it.\n' >>"$rec/brief.md"
run_runner leading --arms-only
check "a brief that states a view is warned about" err_has "advises against"
check "...and still runs" [ "$status" -eq 0 ]

finish runner
