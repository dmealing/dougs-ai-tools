#!/bin/sh
# challenge-run: dispatch both arms of a challenge in parallel, then write the
# blind differential.
#
#   challenge-run.sh <slug>                 arms, then the differential
#   challenge-run.sh <slug> --arms-only     arms only
#   challenge-run.sh <slug> --reextract     re-read raw arm output already on
#                                           disk (no dispatch), then differential
#   challenge-run.sh <slug> --differential  differential only, from A.md and B.md
#
# Design notes:
#  - Both arms launch through the identical command and differ only in --model.
#    Mixing harnesses would confound a model comparison with a harness one.
#  - --safe-mode is the clean room. Without it an arm inherits the CLAUDE.md of
#    its working directory, its skills and its hooks. The brief is the only
#    context either arm gets, and it goes in on standard input.
#  - Everything that can be refused is refused before the first paid call: an
#    unfilled brief, a missing verification scope, a model string that is not a
#    Claude model, a pair that could be one model, a Fable model without the
#    opt-in, a differential model that is also an arm.
#  - The model is verified from the API's own usage metadata, never by asking
#    the arm. An alias or a [1m] suffix is accepted; a different model is not.
#  - The arms get Read, Grep, Glob and Bash, and no Write or Edit. Bash can still
#    write, so the run fingerprints git-visible state before and after and says
#    so when it changed. It cannot see writes outside the repository.
#  - If one arm fails, the other arm's answer is kept: it is already paid for.
#  - The differential is written by a third model that sees no model names,
#    cannot read the repository and has no tools. It reads the two answers in
#    both orders, so a position effect shows up as disagreement between passes.
#
# POSIX sh, with python3 for JSON; runs on macOS and Linux.

# prog and home_dir are read or set by challenge-common.sh.
# shellcheck disable=SC2034,SC2154

set -eu

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)
prog=challenge-run
# shellcheck source=/dev/null
. "$here/challenge-common.sh"

challenge_home
arm_timeout=${CHALLENGE_ARM_TIMEOUT:-900}
synth_timeout=${CHALLENGE_SYNTH_TIMEOUT:-300}
synth_model=${CHALLENGE_SYNTH_MODEL:-$default_synth_model}
synth_budget=${CHALLENGE_SYNTH_BUDGET_USD:-4}
# The tool set is passed with --tools, which controls what EXISTS. Agent is left
# out on purpose: an arm that fans out to subagents differs from one that does
# not for a reason that is not the model.
tools=${CHALLENGE_ARM_TOOLS:-Read Grep Glob Bash}

usage() {
	cat <<'EOF'
usage: challenge-run.sh <slug> [--arms-only | --reextract | --differential]
environment:
  CHALLENGE_ARM_BUDGET_USD    per-arm cap (default 8; 16 when a Fable model is in the pair)
  CHALLENGE_ARM_TIMEOUT       seconds before an arm is killed (default 900)
  CHALLENGE_SYNTH_MODEL       differential model (default claude-sonnet-5-5); it must
                              not be either arm's model
  CHALLENGE_SYNTH_BUDGET_USD  cap for each differential call (default 4)
  CHALLENGE_SKIP_SCOPE_CHECK  1 to allow a brief that states no verification scope
exit codes: 0 done; 2 refused or failed; 3 only one arm answered; 4 arms done,
differential failed (re-run with --differential)
EOF
}

die() { challenge_die "$1"; }

slug=''
mode=dispatch
arms_only=0
while [ $# -gt 0 ]; do
	case $1 in
	--arms-only) arms_only=1 ;;
	--reextract) mode=reextract ;;
	--differential) mode=differential ;;
	-h | --help)
		usage
		exit 0
		;;
	-*) die "unknown flag $1" ;;
	*)
		[ -z "$slug" ] || die "unexpected argument: $1"
		slug=$1
		;;
	esac
	shift
done
[ -n "$slug" ] || {
	usage >&2
	exit 2
}
check_slug "$slug"
[ "$mode" = differential ] && [ "$arms_only" -eq 1 ] && die "--differential and --arms-only contradict"

d="$home_dir/$slug"
[ -d "$d" ] || die "no record dir for '$slug'; run 'challenge-log.sh new $slug <repo>' first"
d=$(CDPATH='' cd -- "$d" && pwd -P)

work=''
# Run by the trap below.
# shellcheck disable=SC2329
cleanup() { [ -z "$work" ] || rm -rf "$work"; }
trap cleanup EXIT INT TERM

# --- the brief --------------------------------------------------------------

# section_body <heading>: the text under one of the template's headings, up to
# the next template heading. Matching only the template's own headings means a
# "# comment" line in a pasted code block does not end a section.
section_body() {
	awk -v want="$1" '
	BEGIN { n = split("Question|Facts|The strongest case each way|What evidence would settle this either way|Working rules|Output contract", names, "|") }
	{
		hit = 0
		for (i = 1; i <= n; i++) if (index($0, "# " names[i]) == 1) { hit = 1; cur = names[i] }
		if (hit) { in_section = (cur == want); next }
		if (in_section) print
	}' "$d/brief.md"
}

check_brief() {
	brief=$d/brief.md
	[ -s "$brief" ] || die "$brief is empty; write the brief before dispatching"
	[ "$(wc -c <"$brief" | tr -d ' ')" -gt 400 ] || die "the brief is under 400 bytes; that is the empty template, not a brief"
	if grep -qF '{TASK}' "$brief"; then die "the brief still contains the {TASK} placeholder"; fi
	if grep -qiF '<fill in>' "$brief"; then die "the brief still contains a <fill in> placeholder"; fi
	# Each section the brief must fill needs real text under its own heading.
	# The heading text itself never counts, so an untouched template fails here.
	for heading in 'Question' 'Facts' 'The strongest case each way' 'What evidence would settle this either way'; do
		body=$(section_body "$heading" | tr -d '[:space:]')
		[ "${#body}" -ge 20 ] || die "the brief has no text under '# $heading' (fewer than 20 characters). Fill every section before dispatching."
	done
	# A false premise poisons both arms identically, so the brief has to say what
	# was NOT checked. The test reads the Facts text, not the heading.
	if [ "${CHALLENGE_SKIP_SCOPE_CHECK:-0}" != 1 ] &&
		! section_body 'Facts' | grep -qiE 'did not read|have not read|not read|verification scope|not verified|unverified|scope of (my|the) verification|scope:'; then
		die "the Facts section states no verification SCOPE. Say which files you did NOT read and which facts are unverified, then run again.
  Override with CHALLENGE_SKIP_SCOPE_CHECK=1 if the brief genuinely has nothing unverified."
	fi
	# Wording that manufactures agreement or invites a performance. A warning, not
	# a refusal: a quoted example of the wording is not a use of it.
	banned='asked for your|ruling specifically|correctly dismantled|you have been right|has been wrong before|deference|delegated the call|final quality gate|you are the (authority|decider|expert)|(^|[^[:alnum:]])(i|we) (think|believe|am convinced|am sure|are sure)|the other (model|reviewer|adjudicator|reader)|second (reviewer|model|opinion)'
	hits=$(grep -inE "$banned" "$brief" || true)
	if [ -n "$hits" ]; then
		printf 'warning: the brief has wording the skill advises against (authority, deference, a stated view, or a mention of another reader). Edit and run again if it is a real use:\n%s\n' "$hits" >&2
	fi
}

# --- models -----------------------------------------------------------------

read_map() {
	a_model=$(sed -n 's/^A=//p' "$d/.map" 2>/dev/null | head -n 1)
	b_model=$(sed -n 's/^B=//p' "$d/.map" 2>/dev/null | head -n 1)
	[ -n "$a_model" ] && [ -n "$b_model" ] || die "unreadable .map in $d"
	repo=$(sed -n 's/^repo=//p' "$d/.meta" 2>/dev/null | head -n 1)
	optin=$(sed -n 's/^fable_optin=//p' "$d/.meta" 2>/dev/null | head -n 1)
}

# check_models: refuses, before any paid call, everything a model string can get
# wrong. The after-the-fact check on the usage metadata is the second line.
check_models() {
	for candidate in "$a_model" "$b_model" "$synth_model"; do
		valid_model "$candidate" || die "not a Claude model ID or family alias: '$candidate'"
	done
	fable=0
	if is_fable "$a_model" || is_fable "$b_model"; then
		fable=1
		[ "$optin" = yes ] || die "this record has a Fable model but was not created with --fable. Start a new record with 'challenge-log.sh new <slug> <repo> --fable'."
	fi
	if is_fable "$synth_model"; then
		die "the differential model '$synth_model' is a Fable model; pick a cheaper model outside the pair"
	fi
	if [ "$a_model" != "$b_model" ] && models_overlap "$a_model" "$b_model"; then
		die "'$a_model' and '$b_model' could be the same model, so the pair would not differ"
	fi
	if models_overlap "$synth_model" "$a_model" || models_overlap "$synth_model" "$b_model"; then
		die "the differential model '$synth_model' is, or could be, one of the arms' models. It must be outside the pair so it does not grade its own kind. Set CHALLENGE_SYNTH_MODEL."
	fi
	budget=${CHALLENGE_ARM_BUDGET_USD:-}
	if [ -z "$budget" ]; then
		budget=8
		[ "$fable" -eq 1 ] && budget=16
	fi
	for amount in "$budget" "$synth_budget"; do
		case $amount in
		'' | *[!0-9.]* | *.*.*) die "a budget must be a number of dollars: '$amount'" ;;
		esac
	done
	command -v claude >/dev/null 2>&1 || die "claude is not on PATH"
}

# --- running a command with a time limit ------------------------------------

# run_with_timeout <seconds> <stdin file> <stdout file> <stderr file> <command...>
# A portable stand-in for timeout(1), which stock macOS lacks. Returns the
# command's exit status; a command killed at the limit leaves <stdout>.timedout.
run_with_timeout() {
	rwt_secs=$1
	rwt_in=$2
	rwt_out=$3
	rwt_err=$4
	shift 4
	rm -f "$rwt_out.timedout"
	"$@" <"$rwt_in" >"$rwt_out" 2>"$rwt_err" &
	rwt_pid=$!
	(
		rwt_i=0
		while [ "$rwt_i" -lt "$rwt_secs" ]; do
			sleep 1
			kill -0 "$rwt_pid" 2>/dev/null || exit 0
			rwt_i=$((rwt_i + 1))
		done
		: >"$rwt_out.timedout"
		kill "$rwt_pid" 2>/dev/null || true
	) &
	rwt_watch=$!
	rwt_rc=0
	wait "$rwt_pid" || rwt_rc=$?
	kill "$rwt_watch" 2>/dev/null || true
	wait "$rwt_watch" 2>/dev/null || true
	return "$rwt_rc"
}

# --- extracting and verifying a result --------------------------------------

# extract_result <arm|synth> <raw json> <requested model> <answer file> <info file>
# Writes the answer only when the requested model did the reasoning, or the
# differential is well formed. Prints the reason on standard error otherwise.
extract_result() {
	python3 - "$@" <<'PY'
import json, re, sys

kind, raw, want, ansfile, infofile = sys.argv[1:6]
ALIASES = {"opus", "sonnet", "haiku", "fable"}


def norm(model):
    # Drop a [1m]-style suffix and a trailing date, so a suffixed key still
    # compares equal to the canonical ID.
    model = model.lower().split("[")[0]
    return re.sub(r"-\d{8}$", "", model)


def matches(requested, got):
    requested, got = norm(requested), norm(got)
    if requested in ALIASES:
        return got.startswith("claude-%s-" % requested)
    return requested == got


try:
    r = json.load(open(raw))
except Exception as e:
    sys.exit("output is not JSON (%s); see %s" % (e, raw))
if r.get("is_error"):
    sys.exit("reported an error: %s" % str(r.get("result"))[:300])

# The harness bills a few tokens to a small helper model for chores such as
# session titles, so "exactly one model appears" is too strict. What must hold is
# that the model we ASKED for did the reasoning: it appears and holds the most
# output tokens. That still catches a silent fallback.
canon = {}
for key, value in (r.get("modelUsage") or {}).items():
    value = value or {}
    name = value.get("canonicalModel", key)
    canon[name] = canon.get(name, 0) + (value.get("outputTokens", 0) or 0)
if not any(matches(want, name) for name in canon):
    sys.exit("MODEL MISMATCH: asked for %s, the API reports %s. Both arms were billed. "
             "The classifier fallback described in the model documentation can cause this. "
             "The raw output is kept; fix the cause, then --reextract re-reads it for free."
             % (want, sorted(canon) or "nothing"))
main = max(canon, key=canon.get)
if not matches(want, main):
    sys.exit("MODEL MISMATCH: asked for %s but %s produced most of the output (%s). "
             "The raw output is kept for --reextract." % (want, main, canon))
aux = {m: n for m, n in canon.items() if m != main}
ans = (r.get("result") or "").strip()
if len(ans) < 200:
    sys.exit("returned %d chars, too short to be an answer" % len(ans))

if kind == "synth":
    lines = [line for line in ans.splitlines() if line.strip()]
    first = re.match(r"AGREEMENT:\s*(yes|partial|no)\s*$", lines[0]) if lines else None
    if not first:
        sys.exit("the differential does not start with 'AGREEMENT: yes|partial|no'")
    low = ans.lower()
    missing = [h for h in ("converged", "a check settles it", "judgment call",
                           "asymmetric coverage", "shared assumptions") if h not in low]
    if missing:
        sys.exit("the differential lacks section(s): %s" % ", ".join(missing))

open(ansfile, "w").write(ans + "\n")
denials = r.get("permission_denials") or []
with open(infofile, "w") as f:
    f.write("model=%s\nrequested=%s\nsession=%s\ncost_usd=%s\nbytes=%d\nout_tokens=%d\naux=%s\ndenials=%d\n"
            % (main, want, r.get("session_id", ""), r.get("total_cost_usd", ""), len(ans),
               canon[main], aux or "{}", len(denials)))
    for denial in denials[:10]:
        f.write("denied=%s\n" % denial.get("tool_name", "?"))
PY
}

info() { sed -n "s/^$2=//p" "$d/.$1.info" 2>/dev/null | head -n 1; }

# --- arms -------------------------------------------------------------------

# run_arm <model> <slot>: one arm. Identical for every arm; only the model varies.
run_arm() {
	arm_model=$1
	arm_slot=$2
	arm_rc=0
	# $tools is deliberately split into words.
	# shellcheck disable=SC2086
	run_with_timeout "$arm_timeout" "$d/brief.md" "$d/.$arm_slot.json" "$d/.$arm_slot.err" \
		claude -p --model "$arm_model" --safe-mode --output-format json \
		--tools $tools --add-dir "$repo" --max-budget-usd "$budget" || arm_rc=$?
	echo "$arm_rc" >"$d/.$arm_slot.rc"
}

dispatch_arms() {
	[ -n "$repo" ] && [ -d "$repo" ] || die "the recorded repository path is missing or not a directory: '$repo'"
	pre_head=$(git -C "$repo" rev-parse HEAD 2>/dev/null || echo none)
	git -C "$repo" status --porcelain 2>/dev/null | sort >"$d/.pre-status" || true
	pairing=$(pairing_of "$a_model" "$b_model")
	echo "dispatching 2 arms; pairing: $pairing" >&2
	echo "  (order hidden; cwd $repo; safe-mode; no Write or Edit tool; per-arm cap \$$budget, a client-side estimate)" >&2
	cd "$repo"
	run_arm "$a_model" A &
	pid_a=$!
	run_arm "$b_model" B &
	pid_b=$!
	wait "$pid_a" || true
	wait "$pid_b" || true
	post_head=$(git -C "$repo" rev-parse HEAD 2>/dev/null || echo none)
	git -C "$repo" status --porcelain 2>/dev/null | sort >"$d/.post-status" || true
	if [ "$pre_head" != "$post_head" ] || ! cmp -s "$d/.pre-status" "$d/.post-status"; then
		{
			echo ""
			echo "WARNING: the repository CHANGED while the arms ran."
			echo "  HEAD  $pre_head -> $post_head"
			echo "  An arm was expected to read, not write. Inspect 'git -C $repo status' before"
			echo "  trusting these answers, and before committing anything in that repository."
		} >&2
		echo "mutated=yes" >>"$d/.meta"
	fi
	rm -f "$d/.pre-status" "$d/.post-status"
}

# extract_arms: sets $ok_slots and $failed. Each arm is extracted on its own,
# so one failure never discards the other's paid-for answer.
extract_arms() {
	ok_slots=''
	failed=''
	for slot in A B; do
		slot_model=$(sed -n "s/^$slot=//p" "$d/.map" | head -n 1)
		rc=$(cat "$d/.$slot.rc" 2>/dev/null || echo 1)
		if [ "$rc" != 0 ]; then
			why="exited $rc"
			if [ -e "$d/.$slot.json.timedout" ]; then
				why="timed out after ${arm_timeout}s"
			elif grep -qi 'budget limit reached' "$d/.$slot.err" 2>/dev/null; then
				why="BUDGET EXHAUSTED: $(tr -d '\n' <"$d/.$slot.err" | sed 's/  */ /g') (raise CHALLENGE_ARM_BUDGET_USD, now \$$budget, or narrow the brief)"
			fi
			failed="$failed
  - $slot: $why"
			echo "  $slot FAILED: $why" >&2
			continue
		fi
		if extract_result arm "$d/.$slot.json" "$slot_model" "$d/$slot.md" "$d/.$slot.info" 2>"$d/.$slot.reject"; then
			ok_slots="$ok_slots $slot"
			echo "  $slot ok: $(info "$slot" bytes) bytes, $(info "$slot" denials) denials, session $(info "$slot" session)" >&2
		else
			reason=$(cat "$d/.$slot.reject")
			failed="$failed
  - $slot: $reason"
			echo "  $slot FAILED: $reason" >&2
		fi
		rm -f "$d/.$slot.reject"
	done
}

# --- the differential -------------------------------------------------------

# build_prompt <first answer file> <second answer file>
build_prompt() {
	cat <<'EOF'
You are comparing two independent answers to the same brief. You do not know who
or what wrote either answer, and you must not guess. You cannot read the
repository and have no tools: work only from the text below. If an answer cites a
file or command output you cannot see, treat it as that answer's claim.

Write a differential. Do not say which answer is better, do not rank them, and do
not hint at a preference. Where they differ, say how, and what would settle it.

Start your reply with exactly one line:
AGREEMENT: yes     (the two reach the same operational conclusion)
AGREEMENT: partial (they agree on some of it, or on the conclusion for different reasons that matter)
AGREEMENT: no      (their conclusions conflict)

Then use exactly these sections:
## Converged
Same operational conclusion, strictly judged. Say when they reached it by different reasoning.
## Split: a check settles it
Differences that turn on a fact, each with the exact command or file:line that decides it.
## Split: a judgment call
Differences no check can settle because they turn on priorities, risk appetite or
intent. For each: what each position implies, the load-bearing reason each way, and
what being wrong costs each way. This section may be empty, and often should be.
## Asymmetric coverage
What one answer raised that the other never mentioned. Not disagreement.
## Shared assumptions worth doubting
What BOTH took for granted, especially anything the brief asserted that neither verified.

<<<BRIEF>>>
EOF
	cat "$d/brief.md"
	printf '\n<<<END BRIEF>>>\n\n<<<ANSWER 1>>>\n'
	cat "$1"
	printf '\n<<<END ANSWER 1>>>\n\n<<<ANSWER 2>>>\n'
	cat "$2"
	printf '\n<<<END ANSWER 2>>>\n'
}

# synth_pass <number> <first answer file> <second answer file>
synth_pass() {
	pass=$1
	build_prompt "$2" "$3" >"$work/prompt-$pass.txt"
	pass_rc=0
	# The differential runs in an empty folder with no tools, so it cannot read
	# the repository or anything else.
	(
		cd "$work"
		run_with_timeout "$synth_timeout" "$work/prompt-$pass.txt" "$d/.D$pass.json" "$d/.D$pass.err" \
			claude -p --model "$synth_model" --safe-mode --output-format json \
			--tools "" --max-budget-usd "$synth_budget"
	) || pass_rc=$?
	echo "$pass_rc" >"$d/.D$pass.rc"
}

differential() {
	[ -s "$d/A.md" ] && [ -s "$d/B.md" ] || die "the differential needs both $d/A.md and $d/B.md"
	command -v claude >/dev/null 2>&1 || die "claude is not on PATH"
	work=$(mktemp -d "${TMPDIR:-/tmp}/challenge-run.XXXXXX") || die "cannot make a temporary folder"
	echo "writing the differential with $synth_model, answers read in both orders" >&2
	synth_pass 1 "$d/A.md" "$d/B.md" &
	pid_1=$!
	synth_pass 2 "$d/B.md" "$d/A.md" &
	pid_2=$!
	wait "$pid_1" || true
	wait "$pid_2" || true

	good=''
	for pass in 1 2; do
		rc=$(cat "$d/.D$pass.rc" 2>/dev/null || echo 1)
		if [ "$rc" != 0 ]; then
			why="exited $rc"
			[ -e "$d/.D$pass.json.timedout" ] && why="timed out after ${synth_timeout}s"
			echo "  differential pass $pass FAILED: $why" >&2
		elif extract_result synth "$d/.D$pass.json" "$synth_model" "$d/.D$pass.md" "$d/.D$pass.info" 2>"$d/.D$pass.reject"; then
			good="$good $pass"
			echo "  differential pass $pass ok" >&2
		else
			echo "  differential pass $pass FAILED: $(cat "$d/.D$pass.reject")" >&2
		fi
		rm -f "$d/.D$pass.reject"
	done

	if [ -z "$good" ]; then
		echo "challenge-run: both differential passes failed. The arms' answers are intact; run again with --differential." >&2
		return 4
	fi

	agree_1=$(sed -n '1,3s/^AGREEMENT: *\([a-z]*\).*/\1/p' "$d/.D1.md" 2>/dev/null | head -n 1)
	agree_2=$(sed -n '1,3s/^AGREEMENT: *\([a-z]*\).*/\1/p' "$d/.D2.md" 2>/dev/null | head -n 1)
	case $good in
	' 1 2')
		if [ "$agree_1" = "$agree_2" ]; then
			agreement=$agree_1
			note_order="both passes agree"
		else
			agreement=partial
			note_order="the passes DISAGREE ($agree_1 against $agree_2), so the verdict depends on the order the answers are read in; recorded as partial"
		fi
		;;
	' 1')
		agreement=$agree_1
		note_order="only pass 1 succeeded; the order effect is unchecked"
		;;
	*)
		agreement=$agree_2
		note_order="only pass 2 succeeded; the order effect is unchecked"
		;;
	esac

	{
		printf '# Differential\n\n'
		printf 'Written by a model that saw no model names and could not read the repository.\n'
		printf 'The answers are shown in opposite orders in the two passes.\n'
		printf 'Pass 1: Answer 1 is A.md, Answer 2 is B.md. Pass 2: Answer 1 is B.md, Answer 2 is A.md.\n\n'
		printf 'Agreement: %s (%s)\n' "$agreement" "$note_order"
		for pass in $good; do
			printf '\n---\n\n# Pass %s\n\n' "$pass"
			cat "$d/.D$pass.md"
		done
	} >"$d/differential.md"
	printf '%s\n' "$agreement" >"$d/.agreement"

	synth_cost=$(for pass in $good; do info "D$pass" cost_usd; done | awk '{ t += $1 } END { printf "%.4f\n", t }')
	grep -v '^synth_cost_usd=' "$d/.arms" >"$d/.arms.new" 2>/dev/null || true
	printf 'synth_cost_usd=%s\n' "$synth_cost" >>"$d/.arms.new"
	mv "$d/.arms.new" "$d/.arms"
	rm -f "$d"/.D[12].json "$d"/.D[12].rc "$d"/.D[12].md "$d"/.D[12].err "$d"/.D[12].json.timedout
	echo "differential: $d/differential.md"
	echo "agreement: $agreement  ($note_order)"
	echo "differential cost: \$$synth_cost"
	return 0
}

# --- main -------------------------------------------------------------------

read_map
check_models

if [ "$mode" != differential ]; then
	check_brief
fi
cost_notice
[ "$fable" -eq 1 ] && fable_notice

case $mode in
dispatch)
	dispatch_arms
	;;
reextract)
	[ -s "$d/.A.json" ] || [ -s "$d/.B.json" ] || die "no raw arm output to re-extract in $d"
	echo "re-extracting from existing arm output (no dispatch)" >&2
	;;
differential)
	status=0
	differential || status=$?
	exit "$status"
	;;
esac

extract_arms
# The slot names are single letters, so splitting them is the point.
# shellcheck disable=SC2086
set -- $ok_slots
n_ok=$#
survivor=$1
if [ "$n_ok" -eq 0 ]; then
	die "both arms failed:$failed"
fi

: >"$d/.arms"
for slot in $ok_slots; do
	echo "${slot}_session=$(info "$slot" session)" >>"$d/.arms"
done
arm_cost=$(for slot in $ok_slots; do info "$slot" cost_usd; done | awk '{ t += $1 } END { printf "%.4f\n", t }')
echo "cost_usd=$arm_cost" >>"$d/.arms"

if [ "$n_ok" -lt 2 ]; then
	# A one-arm result is not a challenge: with no second opinion to differ from, a
	# differential would manufacture agreement out of a single voice.
	{
		echo ""
		echo "WARNING: only $n_ok of 2 arms produced an answer."
		printf '%s\n' "$failed"
		echo "  The surviving answer is kept at $d/$survivor.md and is worth reading,"
		echo "  but this is NOT a challenge: no differential was written, and none should be."
		echo "  Dispatch again, or record the row void."
		echo "  Raw arm output is kept for 'challenge-run.sh $slug --reextract'."
	} >&2
	echo "answer: $d/$survivor.md"
	echo "arm cost: \$$arm_cost"
	exit 3
fi

# Raw output is discarded only once both arms are safely extracted.
rm -f "$d"/.[AB].json "$d"/.[AB].rc "$d"/.[AB].json.timedout
echo "answers: $d/A.md  $d/B.md"
echo "arm cost: \$$arm_cost"
if [ "$arms_only" -eq 1 ]; then
	exit 0
fi
status=0
differential || status=$?
exit "$status"
