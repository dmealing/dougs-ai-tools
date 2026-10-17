#!/bin/sh
# A stand-in for the claude command, for the tests only. It never contacts a
# model: it records how it was called and prints canned JSON in the shape of
# `claude -p --output-format json`. Copy it to a folder on PATH as `claude`.
#
# It reads these, all optional:
#   STUB_DIR              where it records calls (required)
#   STUB_MODE             ok (default), nocanon (key has a [1m] suffix and no
#                         canonicalModel), alias (reports the canonical ID for an
#                         alias), mismatch (reports a different model)
#   STUB_FAIL_MODEL       an arm asked for this model exits 1 with a budget error
#   STUB_SYNTH_FAIL       1: every differential call exits 1
#   STUB_SYNTH_FAIL_PASS  1 or 2: that differential pass exits 1
#   STUB_SYNTH_BAD        1: the differential has no AGREEMENT line
#   STUB_AGREE_X_FIRST    the AGREEMENT value when the first answer carries
#                         mark X (default yes)
#   STUB_AGREE_Y_FIRST    the same for mark Y (default: the X value)
#   STUB_SLEEP            seconds an arm sleeps before it answers
#   STUB_DIRTY            1: an arm writes a file into its working directory

set -u

[ -n "${STUB_DIR:-}" ] || {
	echo "stub claude: STUB_DIR is not set" >&2
	exit 99
}
mkdir -p "$STUB_DIR"

model=''
tools_given=0
tools_value='<unset>'
prev=''
for arg in "$@"; do
	case $prev in
	--model) model=$arg ;;
	--tools)
		tools_given=1
		tools_value=$arg
		;;
	esac
	prev=$arg
done

id=$$
printf '%s\n' "$@" >"$STUB_DIR/args.$id"
cat >"$STUB_DIR/stdin.$id"
printf '%s\n' "$PWD" >"$STUB_DIR/cwd.$id"

kind=arm
grep -qF '<<<ANSWER 1>>>' "$STUB_DIR/stdin.$id" && kind=synth
printf '%s|%s|%s|%s\n' "$kind" "$model" "$tools_given" "$tools_value" >>"$STUB_DIR/calls.log"

# A neutral mark per model, so the tests can follow an answer through the
# differential without any model name appearing in a prompt.
case $model in
claude-opus-5-5* | opus*) mark=MARKX ;;
*) mark=MARKY ;;
esac

if [ "$kind" = arm ]; then
	[ -n "${STUB_SLEEP:-}" ] && sleep "$STUB_SLEEP"
	if [ "${STUB_FAIL_MODEL:-}" = "$model" ]; then
		echo "Error: budget limit reached" >&2
		exit 1
	fi
	[ "${STUB_DIRTY:-0}" = 1 ] && echo wrote >stub-wrote.txt
	text="Verdict: the stub answer for this brief. $mark. Reasoning: the evidence in the repository settles the question in one direction, and the stub says so at some length so that the answer clears the two hundred character floor the runner demands of a real one. Confidence: high, with nothing left unverified."
else
	if [ "${STUB_SYNTH_FAIL:-0}" = 1 ]; then
		echo "Error: stub differential failure" >&2
		exit 1
	fi
	first=$(sed -n '/<<<ANSWER 1>>>/,/<<<END ANSWER 1>>>/p' "$STUB_DIR/stdin.$id" | grep -o 'MARK[XY]' | head -n 1)
	pass=1
	[ "$first" = MARKY ] && pass=2
	if [ "${STUB_SYNTH_FAIL_PASS:-0}" = "$pass" ]; then
		echo "Error: stub differential failure" >&2
		exit 1
	fi
	agree_x=${STUB_AGREE_X_FIRST:-yes}
	agree_y=${STUB_AGREE_Y_FIRST:-$agree_x}
	agree=$agree_x
	[ "$first" = MARKY ] && agree=$agree_y
	head_line="AGREEMENT: $agree"
	[ "${STUB_SYNTH_BAD:-0}" = 1 ] && head_line="No agreement line here"
	text="$head_line\\n## Converged\\nBoth reach the same conclusion by the same route.\\n## Split: a check settles it\\nNone.\\n## Split: a judgment call\\nNone.\\n## Asymmetric coverage\\nNone raised by only one answer.\\n## Shared assumptions worth doubting\\nBoth trust the brief."
fi

case ${STUB_MODE:-ok} in
nocanon)
	usage="\"${model}[1m]\": {\"outputTokens\": 900}"
	;;
mismatch)
	usage="\"claude-haiku-5-5\": {\"canonicalModel\": \"claude-haiku-5-5\", \"outputTokens\": 900}"
	;;
alias)
	case $model in
	opus) canonical=claude-opus-5-5 ;;
	sonnet) canonical=claude-sonnet-5-5 ;;
	*) canonical=$model ;;
	esac
	usage="\"$model\": {\"canonicalModel\": \"$canonical\", \"outputTokens\": 900}, \"claude-haiku-5-5\": {\"canonicalModel\": \"claude-haiku-5-5\", \"outputTokens\": 20}"
	;;
*)
	usage="\"$model\": {\"canonicalModel\": \"$model\", \"outputTokens\": 900}, \"claude-haiku-5-5\": {\"canonicalModel\": \"claude-haiku-5-5\", \"outputTokens\": 20}"
	;;
esac

printf '{"type":"result","is_error":false,"result":"%s","session_id":"stub-session-%s","total_cost_usd":1.5,"modelUsage":{%s},"permission_denials":[]}\n' \
	"$text" "$id" "$usage"
