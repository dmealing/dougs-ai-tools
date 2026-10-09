#!/bin/sh
# list-handoffs.sh - say which handoff a new session should resume, and why.
#
# Read-only. It reads handoff files, asks git about the current checkout and,
# when the GitHub CLI is installed and working, asks it for pull-request
# states. It never writes, moves or deletes anything, and it does not read
# agent session transcripts or any other undocumented agent state.
#
# Usage: list-handoffs.sh [name]
#   name  optional: all or part of a stream name (a handoff's file name
#         without .md). A match on it outranks every other kind of evidence.
#
# Environment:
#   HANDOFF_DIR, CLAUDE_CONFIG_DIR
#       Where the store is; same meaning as in the handoff skill.
#   PICKUP_STALE_DAYS
#       Age in days after which a handoff is flagged stale. Default 14.
#   PICKUP_DEFAULT_BRANCHES
#       Extra branch names to treat as default branches, separated by spaces.
#   PICKUP_GH
#       The GitHub CLI command to run. Default gh. A name that does not exist
#       turns the pull-request check off.
#   PICKUP_GH_WAIT
#       Seconds to wait for the GitHub CLI before giving up on it. Default 15.
#
# Exit status: 0 when a listing was printed, including an empty one; 2 on a
# usage error. The output format is documented in the pickup README, under
# "What the script prints".
#
# POSIX sh; runs on stock macOS (bash 3.2 as sh, BSD userland) and GNU/Linux.

# Each candidate's facts are stored and read back through eval, which the
# linter cannot follow.
# shellcheck disable=SC2034,SC2154

set -u

nl='
'
tab=$(printf '\t')

usage() {
	cat <<'EOF'
Usage: list-handoffs.sh [name]

Lists the live handoffs for the project of the current directory and says
which one to resume, with the reasons. Reads only; changes nothing.

  name    All or part of a stream name (a handoff's file name without .md).
  --help  Show this text.

Environment: HANDOFF_DIR, CLAUDE_CONFIG_DIR, PICKUP_STALE_DAYS,
PICKUP_DEFAULT_BRANCHES, PICKUP_GH, PICKUP_GH_WAIT. See the pickup README.
EOF
}

die() {
	printf 'list-handoffs.sh: %s\n' "$1" >&2
	exit 2
}

# --- arguments and settings ----------------------------------------------------

name_arg=''
for arg in "$@"; do
	case "$arg" in
	-h | --help)
		usage
		exit 0
		;;
	-*)
		usage >&2
		die "unknown option: $arg"
		;;
	*)
		[ -z "$name_arg" ] || die "give at most one name"
		name_arg=$arg
		;;
	esac
done

stale_days=${PICKUP_STALE_DAYS:-14}
case "$stale_days" in
'' | *[!0-9]*) die "PICKUP_STALE_DAYS must be a whole number of days, got: $stale_days" ;;
esac

gh_cmd=${PICKUP_GH:-gh}
gh_wait=${PICKUP_GH_WAIT:-15}
case "$gh_wait" in
'' | *[!0-9]*) die "PICKUP_GH_WAIT must be a whole number of seconds, got: $gh_wait" ;;
esac

today=$(date +%Y-%m-%d)

# --- helpers -------------------------------------------------------------------

# physical <directory>: its path with symbolic links resolved; fails if it is
# not a directory that can be entered.
physical() {
	(CDPATH='' cd -- "$1" 2>/dev/null && pwd -P)
}

# normalise <text>: lower case, with "/" and spaces turned into "-", the way
# the handoff skill turns a branch name into a stream name.
normalise() {
	# The alphabets are spelled out: not every tr handles character classes.
	printf '%s' "$1" | tr 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' 'abcdefghijklmnopqrstuvwxyz' | sed 's|[/ ]|-|g'
}

# header_field <file> <Field>: the value of the first **Field:** marker in the
# top of the file. The value is the first `backticked` text after the marker,
# or, in an older file without backticks, the text up to the next marker.
header_field() {
	sed -n '1,30p' "$1" 2>/dev/null | awk -v field="$2" '
		{
			marker = "**" field ":**"
			at = index($0, marker)
			if (!at) next
			rest = substr($0, at + length(marker))
			# Several fields share one line; stop at the next marker.
			if (match(rest, /\*\*[A-Za-z][A-Za-z ]*:\*\*/)) rest = substr(rest, 1, RSTART - 1)
			if (match(rest, /`[^`]+`/)) {
				value = substr(rest, RSTART + 1, RLENGTH - 2)
			} else {
				value = rest
				gsub(/^[ \t]+|[ \t]+$/, "", value)
			}
			print value
			exit
		}'
}

# days_between <from> <to>: whole days from one YYYY-MM-DD date to another.
# Fails when either is not a calendar date.
days_between() {
	awk -v from="$1" -v to="$2" '
		function day_number(date, part, y, m, d) {
			if (date !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/) return -1
			split(date, part, "-")
			y = part[1] + 0; m = part[2] + 0; d = part[3] + 0
			if (y < 1 || m < 1 || m > 12 || d < 1 || d > 31) return -1
			if (m <= 2) { y -= 1; m += 12 }
			return 365 * y + int(y / 4) - int(y / 100) + int(y / 400) + int((153 * (m - 3) + 2) / 5) + d
		}
		BEGIN {
			a = day_number(from); b = day_number(to)
			if (a < 0 || b < 0) exit 1
			print b - a
		}'
}

# file_date <file>: the date the file was last modified, as YYYY-MM-DD.
# GNU and BSD stat take different options, so try each.
file_date() {
	stamp=$(stat -c %y "$1" 2>/dev/null) ||
		stamp=$(stat -f %Sm -t %Y-%m-%d "$1" 2>/dev/null) ||
		stamp=''
	printf '%s\n' "$stamp" | cut -c1-10
}

# branch_kind <branch as recorded or as checked out>: none, detached, default
# or named. Only a named branch identifies a stream of work.
branch_kind() {
	case "$1" in
	'' | none) printf 'none\n' ;;
	detached | detached@* | '(detached)') printf 'detached\n' ;;
	*)
		case " $default_branches " in
		*" $1 "*) printf 'default\n' ;;
		*) printf 'named\n' ;;
		esac
		;;
	esac
}

# same_commit <short hash> <short hash>: true when both are known and one is
# the start of the other, because short hashes differ in length from one
# repository to the next.
same_commit() {
	case "$1:$2" in
	:* | *: | unknown:* | *:unknown) return 1 ;;
	esac
	case "$1" in
	"$2"*) return 0 ;;
	esac
	case "$2" in
	"$1"*) return 0 ;;
	esac
	return 1
}

# commit_relation <hash from the handoff>: how this checkout stands to that
# commit, as one line for a weak: entry. Needs a git checkout in $here.
commit_relation() {
	case "$1" in
	'' | *[!0-9a-fA-F]*) ;;
	*)
		if git -C "$here" rev-parse --verify --quiet "$1^{commit}" >/dev/null 2>&1; then
			if [ "$(git -C "$here" rev-parse "$1^{commit}")" = "$(git -C "$here" rev-parse HEAD)" ]; then
				printf 'commit +0 this checkout is at the recorded commit %s\n' "$1"
			elif git -C "$here" merge-base --is-ancestor "$1^{commit}" HEAD 2>/dev/null; then
				printf 'commit +0 this checkout is %s commit(s) ahead of the recorded commit %s\n' \
					"$(git -C "$here" rev-list --count "$1^{commit}..HEAD")" "$1"
			elif git -C "$here" merge-base --is-ancestor HEAD "$1^{commit}" 2>/dev/null; then
				printf 'commit +0 this checkout is %s commit(s) behind the recorded commit %s\n' \
					"$(git -C "$here" rev-list --count "HEAD..$1^{commit}")" "$1"
			else
				printf 'commit +0 this checkout and the recorded commit %s have diverged\n' "$1"
			fi
			return 0
		fi
		;;
	esac
	printf 'commit +0 the recorded commit %s is not in this repository\n' "$1"
}

# branch_exists <repository directory> <branch>: true when the branch exists
# there as a local branch or as a remote-tracking branch.
branch_exists() {
	git -C "$1" show-ref --verify --quiet "refs/heads/$2" 2>/dev/null && return 0
	[ -n "$(git -C "$1" for-each-ref --count=1 --format=x "refs/remotes/*/$2" 2>/dev/null)" ]
}

# common_dir <directory>: the git directory that every worktree of the
# repository holding that directory shares. Two checkouts with the same one
# are the same repository. Fails outside a repository.
common_dir() {
	(
		CDPATH='' cd -- "$1" 2>/dev/null || exit 1
		shared=$(git rev-parse --git-common-dir 2>/dev/null) || exit 1
		CDPATH='' cd -- "$shared" 2>/dev/null && pwd -P
	)
}

# pull_request_rows: one line per recent pull request of this repository, as
# STATE<tab>NUMBER<tab>BRANCH<tab>DATE-CLOSED, newest first. Fails when the
# GitHub CLI fails.
# A watchdog stops a call that hangs, because stock macOS has no command that
# limits how long another command may run.
pull_request_rows() {
	"$gh_cmd" pr list --state all --limit 200 \
		--json state,number,headRefName,isCrossRepository,closedAt \
		--jq '.[] | select(.isCrossRepository | not) | [.state, (.number | tostring), .headRefName, ((.closedAt // "")[0:10])] | @tsv' \
		2>/dev/null &
	gh_pid=$!
	(
		sleep "$gh_wait"
		kill "$gh_pid" 2>/dev/null
	) >/dev/null 2>&1 &
	watchdog=$!
	# The redirections keep a shell from reporting the stopped job.
	wait "$gh_pid" 2>/dev/null
	gh_status=$?
	kill "$watchdog" 2>/dev/null
	wait "$watchdog" 2>/dev/null
	return "$gh_status"
}

# pull_request_state <branch> <date the handoff was written, or nothing>:
# "open #N", "merged #N", "closed #N", "earlier #N" or "none-found", from the
# rows fetched above. An open pull request wins, so a branch that was merged
# once and is in review again reads as open. A pull request that was finished
# before the handoff was written is "earlier": it belongs to older work on a
# branch name that has been used again, and says nothing about this handoff.
pull_request_state() {
	printf '%s\n' "$pr_rows" | awk -F '\t' -v branch="$1" -v written="$2" '
		$3 == branch {
			if ($1 == "OPEN") { if (!o) o = $2 }
			else if (written != "" && $4 != "" && $4 < written) { if (!e) e = $2 }
			else if ($1 == "MERGED") { if (!m) m = $2 }
			else if ($1 == "CLOSED") { if (!c) c = $2 }
		}
		END {
			if (o) print "open #" o
			else if (m) print "merged #" m
			else if (c) print "closed #" c
			else if (e) print "earlier #" e
			else print "none-found"
		}'
}

# The candidate evidence lines all repeat the same two-space indent and trailing
# newline. Writing that bookkeeping once keeps the frozen output format in one
# place. Each appends to the caller's reasons/flags variable.
add_reason() { reasons="$reasons  reason: $1$nl"; }
add_weak() { reasons="$reasons  weak: $1$nl"; }
add_flag() { flags="$flags  flag: $1$nl"; }

# --- the store and the project: the handoff skill's own rule ---------------------

if [ -z "${HANDOFF_DIR:-}" ] && [ -z "${CLAUDE_CONFIG_DIR:-}" ] && [ -z "${HOME:-}" ]; then
	die "none of HANDOFF_DIR, CLAUDE_CONFIG_DIR and HOME is set"
fi

# These lines are the rule in the handoff skill, unchanged. A handoff looked
# for under any other name is a handoff nobody finds.
main=$(git worktree list --porcelain 2>/dev/null | sed -n '1s/^worktree //p')
bare=$(git worktree list --porcelain 2>/dev/null | sed -n '2s/^bare$/yes/p')
project=$(basename "${main:-$PWD}")
if [ -n "$bare" ]; then case "$project" in .bare | .git) project=$(basename "$(dirname "$main")") ;; *.git) project=${project%.git} ;; esac; fi
root="${HANDOFF_DIR:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/handoffs}"
# Printed paths have to be usable from any directory.
case "$root" in
/*) ;;
*) root="$PWD/$root" ;;
esac
# Before the bare-clone rule, a repository laid out that way was filed under the
# bare directory's own name. Files written then are still looked for, but only
# when they are known to belong to this repository.
legacy_project=$(basename "${main:-$PWD}")
[ "$legacy_project" != "$project" ] || legacy_project=''

# --- this checkout -----------------------------------------------------------------

in_git=0
checkout=$PWD
if git rev-parse --git-dir >/dev/null 2>&1; then
	in_git=1
	top=$(git rev-parse --show-toplevel 2>/dev/null) || top=''
	[ -z "$top" ] || checkout=$top
fi
here=$(physical "$checkout") || here=$checkout
here_common=''
if [ "$in_git" -eq 1 ]; then
	here_common=$(common_dir "$here") || here_common=''
fi

default_branches='main master trunk develop'
if [ "$in_git" -eq 1 ]; then
	# The branch the remote calls its default, when git knows it.
	remote_head=$(git symbolic-ref --short -q refs/remotes/origin/HEAD 2>/dev/null) || remote_head=''
	[ -z "$remote_head" ] || default_branches="$default_branches ${remote_head#origin/}"
fi
default_branches="$default_branches ${PICKUP_DEFAULT_BRANCHES:-}"

current_commit=''
if [ "$in_git" -eq 0 ]; then
	current_branch=none
elif current_branch=$(git symbolic-ref --short -q HEAD 2>/dev/null) && [ -n "$current_branch" ]; then
	:
else
	current_commit=$(git rev-parse --short HEAD 2>/dev/null) || current_commit=''
	current_branch="detached@${current_commit:-unknown}"
fi
current_kind=$(branch_kind "$current_branch")

case "$current_kind" in
named) branch_note='named branch' ;;
default) branch_note='default branch' ;;
detached) branch_note='detached HEAD' ;;
*) branch_note='not a git repository' ;;
esac

wanted=''
if [ -n "$name_arg" ]; then
	wanted=$(normalise "${name_arg%.md}")
fi

# --- pass 1: find the candidates and weigh each one -----------------------------------

# Each candidate's facts are kept in variables named c_<fact>_<index>.
count=0
skipped=''
named_branches=0

# A pattern does not match a folder whose name starts with a dot, which is what
# the old name of a bare-clone layout usually is.
legacy_folder=''
case "$legacy_project" in
.?*) legacy_folder="$root/$legacy_project/" ;;
esac
for folder in "$root"/*/ "$legacy_folder"; do
	[ -d "$folder" ] || continue
	folder=${folder%/}
	folder_name=$(basename "$folder")
	# Only the top level of a project folder is live; done/ below it is never read.
	for file in "$folder"/*.md; do
		[ -f "$file" ] || continue

		# The project named inside the file decides; the folder name is used
		# only for a file that does not name one.
		recorded_project=$(header_field "$file" Project)
		legacy=0
		if [ -n "$recorded_project" ]; then
			if [ "$recorded_project" = "$project" ]; then
				if [ "$folder_name" = "$project" ]; then
					found_by='project header'
				else
					found_by="project header; the file sits in folder \"$folder_name\", not \"$project\""
				fi
			elif [ -n "$legacy_project" ] && [ "$recorded_project" = "$legacy_project" ]; then
				legacy=1
			else
				if [ "$folder_name" = "$project" ]; then
					skipped="${skipped}skipped: $file (its **Project:** header names \"$recorded_project\")$nl"
				fi
				continue
			fi
		elif [ "$folder_name" = "$project" ]; then
			found_by='folder name; the file has no **Project:** header'
		elif [ -n "$legacy_project" ] && [ "$folder_name" = "$legacy_project" ]; then
			legacy=1
		else
			continue
		fi

		# A file filed under the old name of a bare-clone layout is this
		# repository's only if its recorded checkout says so. The old name was
		# shared by every repository laid out that way.
		legacy_unconfirmed=0
		if [ "$legacy" -eq 1 ]; then
			legacy_repo=$(header_field "$file" Repo)
			legacy_dir=''
			if [ -n "$legacy_repo" ] && legacy_dir=$(physical "$legacy_repo"); then
				legacy_common=$(common_dir "$legacy_dir") || legacy_common=''
				if [ -n "$legacy_common" ] && [ "$legacy_common" = "$here_common" ]; then
					found_by="old project name \"$legacy_project\"; its recorded checkout belongs to this repository"
				else
					# Another repository's file under the shared old name.
					continue
				fi
			else
				found_by="old project name \"$legacy_project\"; its recorded checkout cannot be checked"
				legacy_unconfirmed=1
			fi
		fi

		count=$((count + 1))
		stream=$(basename "$file" .md)
		recorded_repo=$(header_field "$file" Repo)
		recorded_branch=$(header_field "$file" Branch)
		recorded_branch=${recorded_branch%% *}
		recorded_kind=$(branch_kind "$recorded_branch")

		score=0
		reasons=''
		flags=''
		name_matched=0
		if [ "$legacy_unconfirmed" -eq 1 ]; then
			add_flag "legacy-project filed under the old project name \"$legacy_project\"; it may belong to another repository"
		fi

		# When it was written: the header's date, never the file's time unless
		# the header has none.
		written=$(header_field "$file" Written |
			sed -n 's/^[^0-9]*\([0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]\).*/\1/p')
		written_note=''
		if [ -n "$written" ] && age=$(days_between "$written" "$today"); then
			:
		else
			written=$(file_date "$file")
			if age=$(days_between "$written" "$today"); then
				written_note=' (file time; no usable **Written:** header)'
			else
				written=unknown
				age=''
			fi
			add_flag "header-incomplete no usable **Written:** date"
		fi
		if [ -z "$age" ]; then
			age_text='age unknown'
		elif [ "$age" -lt 0 ]; then
			age_text="dated $((0 - age)) day(s) in the future"
		elif [ "$age" -eq 0 ]; then
			age_text='today'
		else
			age_text="$age day(s) ago"
		fi
		if [ -n "$age" ] && [ "$age" -gt "$stale_days" ]; then
			add_flag "stale written $age days ago, limit $stale_days"
		fi

		# The name the user gave.
		if [ -n "$wanted" ]; then
			stream_key=$(normalise "$stream")
			case "$stream_key" in
			"$wanted")
				score=$((score + 200))
				name_matched=1
				add_reason "name-exact +200 the name given is this stream's name"
				;;
			*"$wanted"*)
				score=$((score + 100))
				name_matched=1
				add_reason "name-partial +100 the name given is part of this stream's name"
				;;
			esac
		fi

		# The checkout it was written in. $elsewhere is 1 when that checkout
		# exists and belongs to a repository other than this one.
		elsewhere=0
		recorded_repo_dir=''
		if [ -z "$recorded_repo" ]; then
			add_flag "header-incomplete no **Repo:** path"
		elif recorded_repo_dir=$(physical "$recorded_repo"); then
			if [ "$recorded_repo_dir" = "$here" ]; then
				score=$((score + 40))
				add_reason "repo-path +40 the recorded repository path is this checkout"
			else
				add_flag "different-checkout the recorded repository path exists and is not this checkout"
				recorded_common=$(common_dir "$recorded_repo_dir") || recorded_common=''
				if [ -z "$recorded_common" ] || [ "$recorded_common" != "$here_common" ]; then
					elsewhere=1
				fi
			fi
		else
			recorded_repo_dir=''
			add_flag "repo-missing the recorded repository path no longer exists"
		fi

		# The branch it was written on.
		if [ -z "$recorded_branch" ]; then
			add_flag "header-incomplete no **Branch:** name"
		fi
		case "$recorded_kind" in
		named)
			[ "$elsewhere" -eq 1 ] || named_branches=$((named_branches + 1))
			if [ "$recorded_branch" = "$current_branch" ]; then
				score=$((score + 40))
				add_reason "branch +40 the recorded branch is the branch checked out here"
			else
				add_flag "different-branch recorded on $recorded_branch; here is $current_branch"
			fi
			;;
		default)
			if [ "$recorded_branch" = "$current_branch" ]; then
				add_weak "default-branch +0 both are on $current_branch; a default branch does not identify a stream"
			fi
			;;
		detached)
			if [ "$current_kind" = detached ]; then
				recorded_commit=${recorded_branch#detached@}
				[ "$recorded_commit" != "$recorded_branch" ] || recorded_commit=''
				if [ "$recorded_branch" = "$current_branch" ] || same_commit "$recorded_commit" "$current_commit"; then
					same='the same commit'
				else
					same='not the same commit'
					# Only the path matched, and the commit has moved: a reused
					# checkout, not the same work.
					if [ -n "$recorded_commit" ] && [ -n "$current_commit" ]; then
						add_flag "different-commit recorded detached at $recorded_commit; here is detached at $current_commit"
					fi
				fi
				add_weak "detached +0 both are on a detached HEAD ($same); a detached HEAD does not identify a stream"
			fi
			;;
		esac

		# Where this checkout stands against the commit the handoff recorded.
		# Older files have no such line; that is not a flag.
		recorded_commit=$(header_field "$file" Commit)
		recorded_commit=${recorded_commit%% *}
		if [ -n "$recorded_commit" ] && [ "$in_git" -eq 1 ]; then
			add_weak "$(commit_relation "$recorded_commit")"
		fi

		# A recorded branch, default or not, that no repository able to hold
		# it still has. This is how a renamed default branch shows up.
		case "$recorded_kind" in
		named | default)
			looked=0
			found=0
			if [ "$in_git" -eq 1 ]; then
				looked=1
				if branch_exists "$here" "$recorded_branch"; then found=1; fi
			fi
			if [ "$found" -eq 0 ] && [ -n "$recorded_repo_dir" ] && [ "$recorded_repo_dir" != "$here" ] &&
				git -C "$recorded_repo_dir" rev-parse --git-dir >/dev/null 2>&1; then
				looked=1
				if branch_exists "$recorded_repo_dir" "$recorded_branch"; then found=1; fi
			fi
			if [ "$looked" -eq 1 ] && [ "$found" -eq 0 ]; then
				add_flag "branch-missing the recorded branch no longer exists"
			fi
			;;
		esac

		eval "c_file_$count=\$file c_stream_$count=\$stream c_repo_$count=\$recorded_repo"
		eval "c_branch_$count=\$recorded_branch c_kind_$count=\$recorded_kind"
		eval "c_written_$count=\$written c_written_note_$count=\$written_note c_age_text_$count=\$age_text"
		eval "c_found_by_$count=\$found_by c_score_$count=\$score c_name_matched_$count=\$name_matched"
		eval "c_reasons_$count=\$reasons c_flags_$count=\$flags c_elsewhere_$count=\$elsewhere"
	done
done

# --- pass 2: pull requests, asked for once -------------------------------------------

pr_rows=''
if [ "$named_branches" -eq 0 ]; then
	pr_check='not-needed (no candidate records a branch of this repository that could have a pull request)'
elif [ "$in_git" -eq 0 ]; then
	pr_check='not-needed (not a git repository)'
elif ! command -v "$gh_cmd" >/dev/null 2>&1; then
	pr_check='unavailable (the GitHub CLI was not found)'
elif pr_rows=$(pull_request_rows); then
	pr_check='checked'
else
	pr_rows=''
	pr_check='unavailable (the GitHub CLI failed: not a GitHub repository, not signed in, or offline)'
fi

index=1
while [ "$index" -le "$count" ]; do
	eval "kind=\$c_kind_$index branch=\$c_branch_$index flags=\$c_flags_$index"
	eval "elsewhere=\$c_elsewhere_$index written=\$c_written_$index"
	if [ "$kind" != named ]; then
		pr='not-applicable'
	elif [ "$elsewhere" -eq 1 ]; then
		# This repository's pull requests say nothing about another one's branch.
		pr='not-checked (recorded in another repository)'
	elif [ "$pr_check" != checked ]; then
		# Not checked is not the same as no pull request.
		pr='unknown'
	else
		[ "$written" != unknown ] || written=''
		pr=$(pull_request_state "$branch" "$written")
		case "$pr" in
		merged*) add_flag "pr-merged the pull request for $branch is merged (${pr#merged })" ;;
		closed*) add_flag "pr-closed the pull request for $branch was closed without merging (${pr#closed })" ;;
		esac
	fi
	eval "c_pr_$index=\$pr c_flags_$index=\$flags"
	index=$((index + 1))
done

# --- rank: score, then newest, then name ------------------------------------------------

keys=''
index=1
while [ "$index" -le "$count" ]; do
	eval "score=\$c_score_$index written=\$c_written_$index stream=\$c_stream_$index"
	[ "$written" != unknown ] || written='0000-00-00'
	keys="$keys$score$tab$written$tab$index$tab$stream$nl"
	index=$((index + 1))
done
order=$(printf '%s' "$keys" | LC_ALL=C sort -t "$tab" -k1,1nr -k2,2r -k4 | cut -f3)

top_score=0
second_score=0
tied=0
name_matches=0
rank=0
for index in $order; do
	rank=$((rank + 1))
	eval "score=\$c_score_$index matched=\$c_name_matched_$index"
	name_matches=$((name_matches + matched))
	if [ "$rank" -eq 1 ]; then top_score=$score; fi
	if [ "$rank" -eq 2 ]; then second_score=$score; fi
	if [ "$score" -eq "$top_score" ]; then tied=$((tied + 1)); fi
done

# --- decide ------------------------------------------------------------------------------
#   single     one live handoff, and it is the only thing that could be meant
#   clear      several, and one has stronger evidence than every other
#   ambiguous  several, and the best ones cannot be told apart
#   none       nothing to propose
notes=''
if [ ! -d "$root" ]; then
	notes="${notes}note: the store does not exist; the handoff skill creates it when it writes its first handoff$nl"
fi
if [ "$count" -eq 0 ]; then
	confidence=none
elif [ -n "$wanted" ] && [ "$name_matches" -eq 0 ]; then
	confidence=none
	notes="${notes}note: no stream name matches \"$name_arg\"$nl"
elif [ "$count" -eq 1 ]; then
	confidence=single
elif [ "$top_score" -gt "$second_score" ]; then
	confidence=clear
else
	confidence=ambiguous
	notes="${notes}note: the first $tied candidates have equal evidence; they are listed newest first, and a newer date does not decide$nl"
fi

proposed='none'
action='ask'
case "$confidence" in
single | clear)
	first=${order%%"$nl"*}
	eval "proposed=\"1 \$c_stream_$first\" flags=\$c_flags_$first"
	# Only an unflagged proposal may be loaded without a question.
	[ -n "$flags" ] || action='load'
	;;
none)
	[ "$count" -ne 0 ] || action='none'
	;;
esac

archived=0
for file in "$root/$project/done"/*.md; do
	[ -f "$file" ] || continue
	archived=$((archived + 1))
done

# --- print ---------------------------------------------------------------------------------

printf 'pickup: format 1\n'
if [ -d "$root" ]; then
	printf 'store: %s\n' "$root"
else
	printf 'store: %s (does not exist)\n' "$root"
fi
printf 'project: %s\n' "$project"
printf 'checkout: %s\n' "$here"
printf 'branch: %s (%s)\n' "$current_branch" "$branch_note"
printf 'name: %s\n' "${name_arg:-(not given)}"
printf 'stale-after-days: %s\n' "$stale_days"
printf 'pr-check: %s\n' "$pr_check"
printf 'candidates: %s\n' "$count"
printf 'archived: %s\n' "$archived"
printf 'confidence: %s\n' "$confidence"
printf 'proposed: %s\n' "$proposed"
printf 'action: %s\n' "$action"
printf '%s' "$notes"
printf '%s' "$skipped"

rank=0
for index in $order; do
	rank=$((rank + 1))
	eval "file=\$c_file_$index stream=\$c_stream_$index repo=\$c_repo_$index branch=\$c_branch_$index"
	eval "written=\$c_written_$index written_note=\$c_written_note_$index age_text=\$c_age_text_$index"
	eval "found_by=\$c_found_by_$index score=\$c_score_$index pr=\$c_pr_$index"
	eval "reasons=\$c_reasons_$index flags=\$c_flags_$index"
	printf '\n[%s] %s\n' "$rank" "$stream"
	printf '  path: %s\n' "$file"
	printf '  written: %s, %s%s\n' "$written" "$age_text" "$written_note"
	printf '  recorded-repo: %s\n' "${repo:-(not recorded)}"
	printf '  recorded-branch: %s\n' "${branch:-(not recorded)}"
	printf '  found-by: %s\n' "$found_by"
	printf '  pr: %s\n' "$pr"
	printf '  score: %s\n' "$score"
	printf '%s' "${reasons:-  reason: none$nl}"
	printf '%s' "${flags:-  flag: none$nl}"
done
