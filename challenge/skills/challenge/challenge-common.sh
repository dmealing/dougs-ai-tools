#!/bin/sh
# Shared by challenge-log.sh and challenge-run.sh: source it, do not run it.
#
# The caller sets $prog (its own name, used in messages) before it calls
# anything here.
#
# POSIX sh; runs on macOS and Linux.

# The caller sets prog; the variables below and $home_dir are read by the callers.
# shellcheck disable=SC2154,SC2034

# The default pair crosses two Opus generations. Fable is opt-in: it costs
# 2.5 times as much per token and can bill usage credits under -p.
default_model_a=claude-opus-5-5
default_model_b=claude-opus-5
default_fable_model=claude-fable-5-1
default_synth_model=claude-sonnet-5-5

challenge_die() {
	printf '%s: %s\n' "$prog" "$1" >&2
	exit 2
}

# challenge_home: sets $home_dir, the folder that holds the records.
challenge_home() {
	if [ -n "${CHALLENGE_HOME:-}" ]; then
		home_dir=$CHALLENGE_HOME
	elif [ -n "${CLAUDE_CONFIG_DIR:-}" ]; then
		home_dir=$CLAUDE_CONFIG_DIR/challenge-log
	elif [ -n "${HOME:-}" ]; then
		home_dir=$HOME/.claude/challenge-log
	else
		challenge_die "none of CHALLENGE_HOME, CLAUDE_CONFIG_DIR or HOME is set"
	fi
}

# check_slug <slug>: a slug becomes a folder name, so it may not climb out.
check_slug() {
	case $1 in
	'' | *[!A-Za-z0-9._-]* | .*) challenge_die "a slug is letters, digits, dot, underscore and dash, and does not start with a dot: '$1'" ;;
	esac
}

# norm_model <id>: lower case, without a [1m]-style suffix or a trailing
# 8-digit date, so an alias-era string and a canonical ID compare equal.
norm_model() {
	norm_value=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
	norm_value=${norm_value%%\[*}
	case $norm_value in
	claude-*-[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]) norm_value=${norm_value%-*} ;;
	esac
	printf '%s' "$norm_value"
}

# model_is_alias <normalised id>: a bare family name such as opus.
model_is_alias() {
	case $1 in
	opus | sonnet | haiku | fable) return 0 ;;
	esac
	return 1
}

# valid_model <id>: a family alias, or a claude-<family>-<version> ID.
valid_model() {
	valid_value=$(norm_model "$1")
	model_is_alias "$valid_value" && return 0
	case $valid_value in
	claude-[a-z]*-[0-9]*) return 0 ;;
	esac
	return 1
}

# model_family <id>: opus, sonnet, haiku, fable or another family name.
model_family() {
	family_value=$(norm_model "$1")
	if model_is_alias "$family_value"; then
		printf '%s' "$family_value"
		return 0
	fi
	family_value=${family_value#claude-}
	printf '%s' "${family_value%%-*}"
}

# is_fable <id>: the model is in the Fable family.
is_fable() {
	[ "$(model_family "$1")" = fable ]
}

# models_overlap <id> <id>: the two could be the same model. An alias such as
# opus overlaps every model of its family, because it may resolve to any.
models_overlap() {
	overlap_a=$(norm_model "$1")
	overlap_b=$(norm_model "$2")
	[ "$overlap_a" = "$overlap_b" ] && return 0
	if model_is_alias "$overlap_a"; then
		case $overlap_b in
		"claude-$overlap_a"-*) return 0 ;;
		esac
	fi
	if model_is_alias "$overlap_b"; then
		case $overlap_a in
		"claude-$overlap_b"-*) return 0 ;;
		esac
	fi
	return 1
}

# pairing_of <id> <id>: the two IDs in sorted order, joined by +. It never
# says which arm is which.
pairing_of() {
	printf '%s\n%s\n' "$1" "$2" | sort | paste -sd+ -
}

# cost_notice: what a run costs, on standard error.
cost_notice() {
	cat >&2 <<'NOTICE'
cost: a run starts two headless claude -p sessions (one per arm), then a
  differential step of two calls on a third model. On a subscription login that
  uses plan quota; with an API key it is metered money. The per-arm budget cap
  is a client-side estimate and can be passed.
NOTICE
}

# fable_notice: the extra warning when a Fable model is in the pair.
fable_notice() {
	cat >&2 <<'NOTICE'
warning: a Fable model is in this pair. It costs 2.5 times as much per token
  as Opus 5.5 at list prices. Under claude -p, Claude Code does not ask before
  a Fable request bills to usage credits, so a subscriber can be charged
  without a prompt. Confirm your plan's Fable billing before you dispatch.
NOTICE
}
