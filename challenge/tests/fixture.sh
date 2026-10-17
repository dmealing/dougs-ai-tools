#!/bin/sh
# Shared by the challenge tests: source it, do not run it. Source
# lib/test-helpers.sh first, and set $root (the challenge folder) and $repo.
#
# It builds a throwaway world: a home folder, a record store, a git repository
# for the arms to read, and a stub `claude` first on PATH. No model is called.

# The caller sets these; the variables below are read by the tests that source this.
# shellcheck disable=SC2154,SC2034

skill_dir="$root/skills/challenge"
log_sh="$skill_dir/challenge-log.sh"
run_sh="$skill_dir/challenge-run.sh"

if ! command -v git >/dev/null 2>&1 || ! python3 -c 'import json' >/dev/null 2>&1; then
	printf 'skip - git or python3 not usable; the scripts are not exercised\n'
	exit 0
fi

work=$(mktemp -d "${TMPDIR:-/tmp}/challenge-test.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT INT TERM
work=$(CDPATH='' cd -- "$work" && pwd -P)

# Nothing outside $work may be read: no real home, no inherited setting.
unset CLAUDE_CONFIG_DIR CHALLENGE_HOME CHALLENGE_MODEL_A CHALLENGE_MODEL_B CHALLENGE_SYNTH_MODEL \
	CHALLENGE_ARM_BUDGET_USD CHALLENGE_ARM_TIMEOUT CHALLENGE_SYNTH_TIMEOUT CHALLENGE_SKIP_SCOPE_CHECK \
	CHALLENGE_SYNTH_BUDGET_USD
unset STUB_MODE STUB_FAIL_MODEL STUB_SYNTH_FAIL STUB_SYNTH_FAIL_PASS STUB_SYNTH_BAD \
	STUB_AGREE_X_FIRST STUB_AGREE_Y_FIRST STUB_SLEEP STUB_DIRTY
HOME="$work/home"
CHALLENGE_HOME="$work/records"
STUB_DIR="$work/stub"
GIT_CEILING_DIRECTORIES="$work"
GIT_CONFIG_NOSYSTEM=1
GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.invalid
GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.invalid
export HOME CHALLENGE_HOME STUB_DIR GIT_CEILING_DIRECTORIES GIT_CONFIG_NOSYSTEM \
	GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL
mkdir -p "$HOME" "$work/bin"
cp "$root/tests/stub-claude.sh" "$work/bin/claude"
chmod +x "$work/bin/claude"
PATH="$work/bin:$PATH"
export PATH

target="$work/target"
git init -q "$target"
git -C "$target" commit -q --allow-empty -m 'initial'

# new_record <slug> [flags...]: creates a record for $target; its folder is $rec.
new_record() {
	nr_slug=$1
	shift
	sh "$log_sh" new "$nr_slug" "$target" "$@" >/dev/null 2>&1
	rec="$CHALLENGE_HOME/$nr_slug"
}

# write_brief <file>: a complete brief, including a verification scope.
write_brief() {
	cat >"$1" <<'BRIEF'
# Question

Should the legacy cache layer be removed entirely, or kept behind a flag?

# Facts (state the VERIFICATION SCOPE, not just "verified")

I read src/cache.py and src/server.py in full. I did not read the tests directory
or the deployment scripts. Unverified: whether any external caller still uses the
legacy entry point.

# The strongest case each way

For removal: one code path fewer. Against: a latency regression nobody measured.

# What evidence would settle this either way

A p99 latency benchmark with the cache layer disabled.

# Working rules

The repository in your working directory is READ-ONLY. Do not modify, create or
delete any file in it or anywhere else.

# Output contract

Return your answer as your reply. Use exactly these sections:
  ## Verdict, ## Reasoning, ## What would change my mind, ## Confidence
Ceiling: 800 words. Do not identify yourself, your model, or your provider.
BRIEF
}

# ready_record <slug> [flags...]: a record with a filled-in brief.
ready_record() {
	new_record "$@"
	write_brief "$rec/brief.md"
}

# calls: how many times the stub claude ran.
calls() {
	if [ -f "$STUB_DIR/calls.log" ]; then
		wc -l <"$STUB_DIR/calls.log" | tr -d ' '
	else
		echo 0
	fi
}

# calls_of <kind>: how many of those calls were arms or differential passes.
calls_of() {
	if [ -f "$STUB_DIR/calls.log" ]; then
		grep -c "^$1|" "$STUB_DIR/calls.log" || true
	else
		echo 0
	fi
}

reset_stub() { rm -rf "$STUB_DIR"; }

# holds <shell code>: succeeds when the code does. For checks that combine tests.
holds() { eval "$1"; }

# run_runner <args...>: runs challenge-run.sh; sets $status, and writes
# $work/out (standard output) and $work/err (standard error).
run_runner() {
	status=0
	sh "$run_sh" "$@" >"$work/out" 2>"$work/err" || status=$?
}

# run_with '<NAME=value ...>' <args...>: run_runner with those variables set for
# that one run. Values hold no spaces.
run_with() {
	rw_env=$1
	shift
	(
		for rw_pair in $rw_env; do export "${rw_pair?}"; done
		run_runner "$@"
		printf '%s\n' "$status" >"$work/status"
	)
	status=$(cat "$work/status")
}

# ready_with '<NAME=value ...>' <slug> [flags...]: ready_record with those
# variables set while the record is made.
ready_with() {
	rdw_env=$1
	shift
	(
		for rdw_pair in $rdw_env; do export "${rdw_pair?}"; done
		ready_record "$@"
	)
	rec="$CHALLENGE_HOME/$1"
}
