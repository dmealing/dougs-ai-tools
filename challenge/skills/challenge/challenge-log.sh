#!/bin/sh
# challenge-log: record keeping for /challenge.
#
#  - `new` draws the A/B assignment itself and hides it in .map, so the mapping
#    is never typed, never mistyped, and not in the presenting agent's context.
#    The blind protects the synthesizer, which is what judges the answers.
#  - `new` pins the repository commit, so a challenge can be replayed.
#  - the default pair is Opus 5.5 with Opus 5. Fable is opt-in with --fable.
#    --twin puts the same model in both arms, to measure the noise floor.
#  - the only measure kept is the disagreement rate. It is derived from the
#    rows, never typed. `partial` counts as a split, not as agreement.
#  - the log is appended to; `void` rewrites it through a temporary file and a
#    rename, so a crash cannot leave half a log.
#
# POSIX sh, with python3 for JSON; runs on macOS and Linux.

# prog and home_dir are read or set by challenge-common.sh.
# shellcheck disable=SC2034,SC2154

set -eu

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)
prog=challenge-log
# shellcheck source=/dev/null
. "$here/challenge-common.sh"

challenge_home
log="$home_dir/challenges.jsonl"

usage() {
	cat <<'EOF'
usage: challenge-log.sh <command> [args]
commands:
  new <slug> <repo-path> [--twin] [--fable]
                         create the record dir, draw the A/B map, pin the commit
  note <slug> [flags]    append the row (derived; the reader types little)
  void <slug> <reason>   exclude a row from the tally (bad brief, aborted run)
  status                 split rate per pairing, with a 95% interval
  list [n]               recent rows (default 10)
new flags:
  --twin   same model in both arms: the noise-floor control
  --fable  allow a Fable model in the pair; read the cost warning first
note flags:
  --agreed <yes|no|partial>  REQUIRED. did the two SUBSTANTIVE verdicts match
                             (partial counts as a split)
  --stakes <high|low>        REQUIRED. what turns on this being right
  --note <text>              one line on where they split
environment:
  CHALLENGE_MODEL_A, CHALLENGE_MODEL_B  the pair (default claude-opus-5-5 and
                                        claude-opus-5); aliases such as opus work
  CHALLENGE_HOME                        where records live (default
                                        ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/challenge-log)
examples:
  challenge-log.sh new drop-legacy-cache path/to/repo
  challenge-log.sh new noise-floor-check path/to/repo --twin
  challenge-log.sh note drop-legacy-cache --stakes high --agreed no --note 'split on invalidation order'
EOF
}

die() { challenge_die "$1"; }

cmd_new() {
	slug=''
	repo=''
	twin=0
	fable=0
	while [ $# -gt 0 ]; do
		case $1 in
		--twin) twin=1 ;;
		--fable) fable=1 ;;
		-*) die "unknown flag $1" ;;
		*)
			if [ -z "$slug" ]; then
				slug=$1
			elif [ -z "$repo" ]; then
				repo=$1
			else
				die "unexpected argument: $1"
			fi
			;;
		esac
		shift
	done
	[ -n "$slug" ] || die "slug required"
	check_slug "$slug"
	[ -n "$repo" ] || die "repo path required; without it the challenge cannot be replayed"
	# Ask git rather than testing for .git: in a worktree .git is a file.
	git -C "$repo" rev-parse --git-dir >/dev/null 2>&1 || die "not a git repo: $repo"
	repo=$(CDPATH='' cd -- "$repo" && pwd -P)

	model_a=${CHALLENGE_MODEL_A:-$default_model_a}
	if [ "$fable" -eq 1 ]; then
		model_b=${CHALLENGE_MODEL_B:-$default_fable_model}
	else
		model_b=${CHALLENGE_MODEL_B:-$default_model_b}
	fi
	[ "$twin" -eq 1 ] && model_b=$model_a

	# Every model is judged before any record exists, so a mistake costs nothing.
	for candidate in "$model_a" "$model_b"; do
		valid_model "$candidate" || die "not a Claude model ID or family alias: '$candidate' (use claude-<family>-<version>, or opus, sonnet, haiku or fable)"
		if is_fable "$candidate" && [ "$fable" -eq 0 ]; then
			fable_notice
			die "'$candidate' is a Fable model; pass --fable to opt in"
		fi
	done
	if [ "$twin" -eq 0 ] && models_overlap "$model_a" "$model_b"; then
		die "'$model_a' and '$model_b' could be the same model, so the pair would not differ. Pick two distinct models, or pass --twin."
	fi

	d="$home_dir/$slug"
	if [ -d "$d" ] && [ -n "$(ls -A "$d" 2>/dev/null)" ]; then
		die "record dir already exists and is not empty: $d (pick another slug; overwriting destroys evidence)"
	fi
	mkdir -p "$d"

	# The assignment is drawn here, not in a model's head.
	if [ "$twin" -eq 1 ]; then
		first=$model_a
		second=$model_a
	else
		bit=$(od -An -N1 -tu1 /dev/urandom | tr -d ' ')
		if [ $((bit % 2)) -eq 0 ]; then
			first=$model_a
			second=$model_b
		else
			first=$model_b
			second=$model_a
		fi
	fi
	printf 'A=%s\nB=%s\n' "$first" "$second" >"$d/.map"

	commit=$(git -C "$repo" rev-parse HEAD 2>/dev/null || true)
	origin=$(git -C "$repo" config --get remote.origin.url 2>/dev/null || true)
	dirty=$(git -C "$repo" status --porcelain 2>/dev/null | head -n 1)
	optin=no
	[ "$fable" -eq 1 ] && optin=yes
	printf 'repo=%s\ncommit=%s\norigin=%s\ncreated=%s\nfable_optin=%s\n' \
		"$repo" "$commit" "$origin" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$optin" >"$d/.meta"

	cat >"$d/brief.md" <<'EOF'
# Question



# Facts (state the VERIFICATION SCOPE, not just "verified")



# The strongest case each way



# What evidence would settle this either way



# Working rules

The repository in your working directory is READ-ONLY. Do not modify, create or
delete any file in it or anywhere else.

# Output contract

Return your answer as your reply. Use exactly these sections:
  ## Verdict           - your answer to the question, first, in one or two sentences
  ## Reasoning         - what in the code or evidence drives it
  ## What would change my mind - concrete and checkable
  ## Confidence        - and what you could not verify
Ceiling: 800 words. If the evidence does not settle the question, say so plainly
rather than picking a side.
Do not identify yourself, your model, or your provider anywhere in the answer.
EOF

	printf '%s\n' "$d"
	if [ -n "$commit" ]; then
		printf 'pinned commit: %s\n' "$(printf '%s' "$commit" | cut -c1-9)" >&2
	else
		echo "WARNING: no commit pinned; this challenge cannot be replayed" >&2
	fi
	[ -n "$dirty" ] && echo "WARNING: the working tree is dirty; the pinned commit is not what the arms will read" >&2
	cost_notice
	if is_fable "$first" || is_fable "$second"; then
		fable_notice
	fi
	echo "next: fill in $d/brief.md, then run challenge-run.sh $slug" >&2
	return 0
}

cmd_note() {
	[ $# -ge 1 ] || die "slug required"
	slug=$1
	shift
	check_slug "$slug"
	stakes=''
	agreed=''
	note=''
	while [ $# -gt 0 ]; do
		case $1 in
		--stakes)
			[ $# -ge 2 ] || die "--stakes needs a value"
			stakes=$2
			shift 2
			;;
		--agreed)
			[ $# -ge 2 ] || die "--agreed needs a value"
			agreed=$2
			shift 2
			;;
		--note)
			[ $# -ge 2 ] || die "--note needs a value"
			note=$2
			shift 2
			;;
		*) die "unknown flag $1" ;;
		esac
	done
	[ -n "$stakes" ] || die "--stakes is required (high|low)"
	[ -n "$agreed" ] || die "--agreed is required (yes|no|partial): whether the two SUBSTANTIVE verdicts matched"
	case $stakes in high | low) ;; *) die "--stakes must be high or low" ;; esac
	case $agreed in yes | no | partial) ;; *) die "--agreed must be yes, no or partial" ;; esac

	d="$home_dir/$slug"
	[ -d "$d" ] || die "no record dir for '$slug'; run 'new' first"
	for f in brief.md A.md B.md .map; do
		[ -s "$d/$f" ] || die "missing or empty $d/$f: a row without its brief and both answers cannot be reread later"
	done

	model_a=$(sed -n 's/^A=//p' "$d/.map" | head -n 1)
	model_b=$(sed -n 's/^B=//p' "$d/.map" | head -n 1)
	[ -n "$model_a" ] && [ -n "$model_b" ] || die "unreadable .map in $d"
	pairing=$(pairing_of "$model_a" "$model_b")
	brief_hash=$(git hash-object -- "$d/brief.md" 2>/dev/null | cut -c1-16 || true)
	a_bytes=$(wc -c <"$d/A.md" | tr -d ' ')
	b_bytes=$(wc -c <"$d/B.md" | tr -d ' ')
	commit=$(sed -n 's/^commit=//p' "$d/.meta" 2>/dev/null | head -n 1)
	a_session=$(sed -n 's/^A_session=//p' "$d/.arms" 2>/dev/null | head -n 1)
	b_session=$(sed -n 's/^B_session=//p' "$d/.arms" 2>/dev/null | head -n 1)
	cost=$(sed -n 's/^cost_usd=//p' "$d/.arms" 2>/dev/null | head -n 1)
	synth_cost=$(sed -n 's/^synth_cost_usd=//p' "$d/.arms" 2>/dev/null | head -n 1)

	mkdir -p "$home_dir"
	python3 - "$log" "$slug" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$stakes" "$agreed" \
		"A=$model_a,B=$model_b" "$pairing" "$commit" "$brief_hash" "$a_bytes" "$b_bytes" \
		"$a_session" "$b_session" "${cost:-0}" "${synth_cost:-0}" "$note" <<'PY'
import json, sys
(log, slug, ts, stakes, agreed, mapping, pairing, commit, brief_hash,
 a_bytes, b_bytes, a_session, b_session, cost, synth_cost, note) = sys.argv[1:17]
row = {
    "slug": slug, "ts": ts, "stakes": stakes, "agreed": agreed,
    "map": mapping, "pairing": pairing, "commit": commit,
    "brief_sha": brief_hash, "a_bytes": int(a_bytes), "b_bytes": int(b_bytes),
    "a_session": a_session, "b_session": b_session,
    "cost_usd": cost, "synth_cost_usd": synth_cost, "note": note,
    "void": False, "void_reason": None,
}
with open(log, "a") as fh:
    fh.write(json.dumps(row) + "\n")
PY
	echo "recorded: $slug  (pairing $pairing, agreed=$agreed)"
}

cmd_void() {
	[ $# -ge 2 ] || die "usage: void <slug> <reason>; say why this row cannot count"
	slug=$1
	shift
	reason=$*
	[ -f "$log" ] || die "no log at $log"
	python3 - "$log" "$slug" "$reason" <<'PY'
import json, os, sys, tempfile
log, slug, reason = sys.argv[1:4]
rows = [json.loads(line) for line in open(log) if line.strip()]
hit = False
for row in reversed(rows):
    if row.get("slug") == slug and not row.get("void"):
        row["void"] = True
        row["void_reason"] = reason
        hit = True
        break
if not hit:
    print("challenge-log: no non-void row for " + slug, file=sys.stderr)
    sys.exit(1)
folder = os.path.dirname(os.path.abspath(log))
fd, tmp = tempfile.mkstemp(dir=folder)
with os.fdopen(fd, "w") as fh:
    fh.write("\n".join(json.dumps(row) for row in rows) + "\n")
os.replace(tmp, log)
print("voided: " + slug + " - " + reason)
PY
}

cmd_status() {
	if [ ! -f "$log" ]; then
		echo "challenges: 0 (none yet)"
		return 0
	fi
	python3 - "$log" <<'PY'
import json, math, sys
from collections import Counter

rows = [json.loads(line) for line in open(sys.argv[1]) if line.strip()]
live = [r for r in rows if not r.get("void")]
print("challenges: %d  (live %d, void %d)" % (len(rows), len(live), len(rows) - len(live)))
high = [r for r in live if r.get("stakes") == "high"]
if not high:
    print("no high-stakes rows yet; low-stakes rows cannot discriminate.")
    raise SystemExit


def wilson(k, n, z=1.96):
    """95% Wilson score interval for k splits in n rows, as percentages."""
    p = k / n
    denom = 1 + z * z / n
    centre = (p + z * z / (2 * n)) / denom
    half = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / denom
    return 100 * max(0.0, centre - half), 100 * min(1.0, centre + half)


total, no, partial = Counter(), Counter(), Counter()
for r in high:
    pairing = r.get("pairing") or "?"
    total[pairing] += 1
    if r.get("agreed") == "no":
        no[pairing] += 1
    elif r.get("agreed") == "partial":
        partial[pairing] += 1

print("\nsplit rate on high-stakes rows (partial counts as a split):")
for pairing, n in sorted(total.items()):
    splits = no[pairing] + partial[pairing]
    lo, hi = wilson(splits, n)
    flag = "  directional only: n < 30" if n < 30 else ""
    print("  %-40s %d/%d  (%d no, %d partial)  %.0f%%  95%% interval %.0f-%.0f%%%s"
          % (pairing, splits, n, no[pairing], partial[pairing], 100 * splits / n, lo, hi, flag))
print("\nA pairing that almost never splits is not earning its second dispatch,")
print("but a small n leaves a wide interval. Read the interval, not the point.")
spend = sum(float(r.get("cost_usd") or 0) + float(r.get("synth_cost_usd") or 0) for r in live)
if spend:
    print("\nclient-side cost estimate recorded: $%.2f" % spend)
PY
}

cmd_list() {
	n=${1:-10}
	case $n in '' | *[!0-9]*) die "list takes a positive integer" ;; esac
	[ "$n" -gt 0 ] || die "list takes a positive integer"
	if [ ! -f "$log" ]; then
		echo "(no records)"
		return 0
	fi
	python3 - "$log" "$n" <<'PY'
import json, sys
rows = [json.loads(line) for line in open(sys.argv[1]) if line.strip()]
for r in rows[-int(sys.argv[2]):]:
    void = "VOID " if r.get("void") else ""
    print("%s  %s%-30s stakes=%-5s agreed=%-7s %s" % (
        r["ts"][:10], void, r["slug"][:30], r.get("stakes") or "?",
        r.get("agreed") or "-", r.get("pairing") or "?"))
PY
}

case ${1:-} in
new)
	shift
	cmd_new "$@"
	;;
note)
	shift
	cmd_note "$@"
	;;
void)
	shift
	cmd_void "$@"
	;;
status)
	shift
	cmd_status "$@"
	;;
list)
	shift
	cmd_list "$@"
	;;
-h | --help | help | '') usage ;;
*) die "unknown command '$1'" ;;
esac
