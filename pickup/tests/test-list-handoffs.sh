#!/bin/sh
# Tests for ../skills/pickup/list-handoffs.sh. Every case builds a throwaway
# handoff store and throwaway git repositories, so the real store, the real
# Claude Code configuration and the network are never touched.
#
# Run: sh pickup/tests/test-list-handoffs.sh

set -u

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)
root=$(dirname -- "$here")
repo=$(dirname -- "$root")
script="$root/skills/pickup/list-handoffs.sh"

# shellcheck source=/dev/null
. "$repo/lib/test-helpers.sh"

if ! command -v git >/dev/null 2>&1; then
	printf 'skip - git not found; list-handoffs.sh not exercised\n'
	exit 0
fi

work=$(mktemp -d "${TMPDIR:-/tmp}/pickup-list-test.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT INT TERM
# The script prints resolved paths; on macOS the temporary folder is a link.
work=$(CDPATH='' cd -- "$work" && pwd -P)

# Nothing outside $work may be read: no real home, no inherited store.
unset HANDOFF_DIR CLAUDE_CONFIG_DIR PICKUP_STALE_DAYS PICKUP_DEFAULT_BRANCHES
HOME="$work/home"
GIT_CEILING_DIRECTORIES="$work"
GIT_CONFIG_NOSYSTEM=1
export HOME GIT_CEILING_DIRECTORIES GIT_CONFIG_NOSYSTEM
mkdir -p "$HOME" "$work/bin"

today=$(date +%Y-%m-%d)
long_ago=2001-02-03

# A stand-in for the GitHub CLI: prints $FAKE_GH_ROWS, or fails.
fake_gh="$work/bin/fake-gh"
cat >"$fake_gh" <<'EOF'
#!/bin/sh
[ "${FAKE_GH_FAIL:-0}" -eq 0 ] || exit 1
printf '%s' "${FAKE_GH_ROWS:-}"
EOF
chmod +x "$fake_gh"
no_gh="$work/bin/no-such-command"

# new_repo <directory> <branch>: a repository with one commit on that branch.
new_repo() {
	mkdir -p "$1"
	(
		cd "$1" &&
			git init -q . &&
			git checkout -q -b "$2" &&
			git -c user.name=test -c user.email=test@example.invalid \
				commit -q --allow-empty -m init
	) >/dev/null 2>&1
}

# write_handoff <store> <folder> <stream> <project> <repo> <branch> <written>
# An empty value leaves that header field out, as an older file would.
# The backticks are literal Markdown, not shell.
# shellcheck disable=SC2016
write_handoff() {
	mkdir -p "$1/$2"
	{
		printf '# Continue - %s\n\n' "$3"
		[ -z "$4" ] || printf '**Project:** `%s`\n' "$4"
		[ -z "$5" ] || printf '**Repo:** `%s`   ' "$5"
		[ -z "$6" ] || printf '**Branch:** `%s`   ' "$6"
		[ -z "$7" ] || printf '**Written:** %s' "$7"
		printf '\n**Start:** `git status --short`\n\n## Still to do\n- nothing real\n'
	} >"$1/$2/$3.md"
}

# list <store> <directory> [args...]: run the script there; sets $status and
# writes $work/out. The pull-request check is off unless $gh says otherwise.
gh=$no_gh
list() {
	list_store=$1
	list_dir=$2
	shift 2
	(cd "$list_dir" && HANDOFF_DIR="$list_store" PICKUP_GH="$gh" sh "$script" "$@") >"$work/out" 2>&1
	status=$?
}
has_line() { grep -qxF -- "$1" "$work/out"; }
has_text() { grep -qF -- "$1" "$work/out"; }
lacks_text() { ! grep -qF -- "$1" "$work/out"; }
# block_has <stream> <text>: the text is inside that candidate's own block.
block_has() {
	awk -v stream="$1" '
		/^\[[0-9]+\] / { inside = (substr($0, index($0, "] ") + 2) == stream) }
		inside { print }' "$work/out" | grep -qF -- "$2"
}
block_lacks() { ! block_has "$1" "$2"; }

# --- a single match --------------------------------------------------------------
store="$work/store-single"
checkout="$work/parcel-tracker"
new_repo "$checkout" fix/label-printer
write_handoff "$store" parcel-tracker fix-label-printer parcel-tracker "$checkout" fix/label-printer "$today"
before=$(cd "$store" && find . | LC_ALL=C sort && find . -type f -exec cksum {} +)
list "$store" "$checkout"
after=$(cd "$store" && find . | LC_ALL=C sort && find . -type f -exec cksum {} +)
check "single: exits 0" [ "$status" -eq 0 ]
check "single: confidence is single" has_line "confidence: single"
check "single: proposes the handoff" has_line "proposed: 1 fix-label-printer"
check "single: action is load" has_line "action: load"
check "single: prints the exact path" has_line "  path: $store/parcel-tracker/fix-label-printer.md"
check "single: gives the repository path as a reason" has_text "reason: repo-path +40"
check "single: gives the branch as a reason" has_text "reason: branch +40"
check "single: shows the header date" has_line "  written: $today, today"
check "single: has no flag" has_line "  flag: none"
check "single: names the project and the branch" has_line "branch: fix/label-printer (named branch)"
check "single: the store is left exactly as it was" [ "$before" = "$after" ]

# From a sub-folder of the checkout the answer is the same.
mkdir -p "$checkout/src/deep"
list "$store" "$checkout/src/deep"
check "single: works from a sub-folder" has_line "proposed: 1 fix-label-printer"

# --- finished handoffs in done/ are never offered ---------------------------------
mkdir -p "$store/parcel-tracker/done"
cp "$store/parcel-tracker/fix-label-printer.md" "$store/parcel-tracker/done/old-stream.md"
list "$store" "$checkout"
check "done: an archived handoff is not a candidate" has_line "candidates: 1"
check "done: an archived handoff is not printed" lacks_text "old-stream"
check "done: the archive is counted" has_line "archived: 1"

# --- several handoffs on a default branch must be ambiguous ---------------------------
store="$work/store-default"
checkout="$work/depot"
new_repo "$checkout" main
write_handoff "$store" depot billing-export depot "$checkout" main "$today"
write_handoff "$store" depot search-index depot "$checkout" main "$today"
write_handoff "$store" depot login-rate-limit depot "$checkout" main "$today"
list "$store" "$checkout"
check "default branch: confidence is ambiguous" has_line "confidence: ambiguous"
check "default branch: nothing is proposed" has_line "proposed: none"
check "default branch: action is ask" has_line "action: ask"
check "default branch: the match is printed as weak" has_text "weak: default-branch +0"
check "default branch: the branch match adds no reason" lacks_text "reason: branch"
check "default branch: says the candidates tie" has_text "note: the first 3 candidates have equal evidence"
check "default branch: lists every candidate" has_line "candidates: 3"
check "default branch: prints each path" has_line "  path: $store/depot/search-index.md"

# master is a default branch too, and so is one named in the environment.
store="$work/store-master"
checkout="$work/ledger"
new_repo "$checkout" master
write_handoff "$store" ledger first ledger "$checkout" master "$today"
write_handoff "$store" ledger second ledger "$checkout" master "$today"
list "$store" "$checkout"
check "default branch: master is treated the same way" has_line "confidence: ambiguous"
store="$work/store-extra-default"
checkout="$work/atlas"
new_repo "$checkout" release-train
write_handoff "$store" atlas first atlas "$checkout" release-train "$today"
write_handoff "$store" atlas second atlas "$checkout" release-train "$today"
(cd "$checkout" && HANDOFF_DIR="$store" PICKUP_GH="$no_gh" PICKUP_DEFAULT_BRANCHES="release-train" \
	sh "$script") >"$work/out" 2>&1
check "default branch: PICKUP_DEFAULT_BRANCHES adds one" has_text "weak: default-branch +0"

# A default-branch match never decides: the repository path does, when only
# one candidate was written in this checkout.
store="$work/store-default-path"
checkout="$work/courier"
new_repo "$checkout" main
new_repo "$work/courier-second-clone" main
write_handoff "$store" courier written-here courier "$checkout" main "$today"
write_handoff "$store" courier written-elsewhere courier "$work/courier-second-clone" main "$today"
list "$store" "$checkout"
check "default branch: the repository path can still decide" has_line "proposed: 1 written-here"
check "default branch: that choice is clear" has_line "confidence: clear"
check "default branch: the other checkout is flagged" block_has written-elsewhere "flag: different-checkout"

# --- two named branches: the one checked out here is clear ---------------------------
store="$work/store-clear"
checkout="$work/orchard"
new_repo "$checkout" feat/ripeness-sensor
(cd "$checkout" && git branch feat/crate-labels) >/dev/null 2>&1
write_handoff "$store" orchard feat-ripeness-sensor orchard "$checkout" feat/ripeness-sensor "$today"
write_handoff "$store" orchard feat-crate-labels orchard "$checkout" feat/crate-labels "$today"
list "$store" "$checkout"
check "clear: confidence is clear" has_line "confidence: clear"
check "clear: proposes the branch checked out here" has_line "proposed: 1 feat-ripeness-sensor"
check "clear: action is load" has_line "action: load"
check "clear: the other candidate is still listed" has_line "[2] feat-crate-labels"
check "clear: the other candidate is flagged as another branch" \
	block_has feat-crate-labels "flag: different-branch recorded on feat/crate-labels; here is feat/ripeness-sensor"
check "clear: the proposal has no flag" block_has feat-ripeness-sensor "flag: none"

# --- a detached head is weak evidence -------------------------------------------------
store="$work/store-detached"
checkout="$work/kiln"
new_repo "$checkout" main
(cd "$checkout" && git checkout -q --detach) >/dev/null 2>&1
sha=$(cd "$checkout" && git rev-parse --short HEAD)
write_handoff "$store" kiln glaze-timer kiln "$checkout" "detached@$sha" "$today"
write_handoff "$store" kiln shelf-planner kiln "$checkout" "detached@$sha" "$today"
list "$store" "$checkout"
check "detached: the branch line says so" has_line "branch: detached@$sha (detached HEAD)"
check "detached: confidence is ambiguous" has_line "confidence: ambiguous"
check "detached: the match is printed as weak" has_text "weak: detached +0 both are on a detached HEAD (the same commit)"
check "detached: action is ask" has_line "action: ask"

# --- a name argument --------------------------------------------------------------------
store="$work/store-default"
checkout="$work/depot"
list "$store" "$checkout" search
check "name: part of a stream name selects it" has_line "proposed: 1 search-index"
check "name: that choice is clear" has_line "confidence: clear"
check "name: the reason is printed" block_has search-index "reason: name-partial +100"
check "name: the name is echoed" has_line "name: search"
check "name: the others are still listed" has_line "candidates: 3"
list "$store" "$checkout" Billing/Export
check "name: a branch-style name is normalised" block_has billing-export "reason: name-exact +200"
list "$store" "$checkout" e
check "name: a name that fits several is ambiguous" has_line "confidence: ambiguous"
list "$store" "$checkout" warehouse
check "name: no match gives confidence none" has_line "confidence: none"
check "name: no match proposes nothing" has_line "proposed: none"
check "name: no match says so" has_line 'note: no stream name matches "warehouse"'
check "name: no match still asks, with the candidates listed" has_line "action: ask"

# A name outranks the branch and the repository path together.
store="$work/store-clear"
checkout="$work/orchard"
list "$store" "$checkout" crate
check "name: outranks branch and path evidence" has_line "proposed: 1 feat-crate-labels"
check "name: a flagged choice still has to be asked about" has_line "action: ask"

# --- a stale handoff is flagged, not hidden ----------------------------------------------
store="$work/store-stale"
checkout="$work/smokehouse"
new_repo "$checkout" fix/brine-ratio
write_handoff "$store" smokehouse fix-brine-ratio smokehouse "$checkout" fix/brine-ratio "$long_ago"
list "$store" "$checkout"
check "stale: the handoff is still the single candidate" has_line "confidence: single"
check "stale: it is flagged" has_text "flag: stale written "
check "stale: the limit is printed" has_line "stale-after-days: 14"
check "stale: action is ask" has_line "action: ask"
# The file itself was created seconds ago; only the header date counts.
check "stale: the date shown is the header's, not the file's" has_text "  written: $long_ago, "
(cd "$checkout" && HANDOFF_DIR="$store" PICKUP_GH="$no_gh" PICKUP_STALE_DAYS=100000 sh "$script") >"$work/out" 2>&1
check "stale: PICKUP_STALE_DAYS moves the limit" has_line "action: load"
(cd "$checkout" && HANDOFF_DIR="$store" PICKUP_STALE_DAYS=soon sh "$script") >"$work/out" 2>&1
check "stale: a limit that is not a number is refused" [ "$?" -eq 2 ]

# --- a recorded repository path that no longer exists ---------------------------------------
store="$work/store-missing-repo"
checkout="$work/lighthouse"
new_repo "$checkout" fix/lamp-rotation
write_handoff "$store" lighthouse fix-lamp-rotation lighthouse "$work/removed-worktree" fix/lamp-rotation "$today"
list "$store" "$checkout"
check "missing path: flagged" has_text "flag: repo-missing"
check "missing path: the branch still counts" has_text "reason: branch +40"
check "missing path: action is ask" has_line "action: ask"

# --- a recorded branch that no longer exists -----------------------------------------------
store="$work/store-missing-branch"
checkout="$work/foundry"
new_repo "$checkout" main
write_handoff "$store" foundry fix-mould-cooling foundry "$checkout" fix/mould-cooling "$today"
list "$store" "$checkout"
check "missing branch: flagged" has_text "flag: branch-missing"
check "missing branch: also flagged as another branch" has_text "flag: different-branch"
check "missing branch: action is ask" has_line "action: ask"
# A default branch that was renamed away is missing too.
write_handoff "$work/store-renamed-default" foundry cooling-rack foundry "$checkout" master "$today"
list "$work/store-renamed-default" "$checkout"
check "missing branch: a default branch that is gone is flagged" has_text "flag: branch-missing"
check "missing branch: and then it has to be asked about" has_line "action: ask"

# --- written in another worktree of the same repository ------------------------------------
store="$work/store-worktree"
checkout="$work/vineyard"
new_repo "$checkout" main
(cd "$checkout" && git worktree add -q "$work/vineyard-press" -b feat/press-schedule) >/dev/null 2>&1
write_handoff "$store" vineyard feat-press-schedule vineyard "$work/vineyard-press" feat/press-schedule "$today"
list "$store" "$checkout"
check "worktree: the main checkout finds the stream" has_line "candidates: 1"
check "worktree: it is flagged as another checkout" has_text "flag: different-checkout"
check "worktree: it is flagged as another branch" has_text "flag: different-branch"
check "worktree: the branch is not reported missing" lacks_text "branch-missing"
check "worktree: action is ask" has_line "action: ask"
list "$store" "$work/vineyard-press"
check "worktree: the worktree shares the project" has_line "project: vineyard"
check "worktree: in the worktree it loads" has_line "action: load"

# --- the project comes from the header, not the folder name -------------------------------
store="$work/store-header"
checkout="$work/widget shop"
new_repo "$checkout" fix/till-rounding
# Filed under the wrong folder, but the header names this project.
write_handoff "$store" misfiled fix-till-rounding "widget shop" "$checkout" fix/till-rounding "$today"
# In this project's folder, but the header names another project.
write_handoff "$store" "widget shop" stray "another project" "$checkout" fix/till-rounding "$today"
# A sibling whose name starts the same way must never be picked up.
write_handoff "$store" widget near-miss widget "$checkout" fix/till-rounding "$today"
write_handoff "$store" "widget shop tools" near-miss-two "widget shop tools" "$checkout" fix/till-rounding "$today"
list "$store" "$checkout"
check "header: project name with a space" has_line "project: widget shop"
check "header: the misfiled handoff is found" has_line "proposed: 1 fix-till-rounding"
check "header: it is the only candidate" has_line "candidates: 1"
check "header: says where it was found" \
	has_line '  found-by: project header; the file sits in folder "misfiled", not "widget shop"'
check "header: a file naming another project is skipped, and shown" \
	has_line "skipped: $store/widget shop/stray.md (its **Project:** header names \"another project\")"
check "header: a sibling project is not matched by its prefix" lacks_text "near-miss"

# --- an older file without the header fields ------------------------------------------------
store="$work/store-old-file"
checkout="$work/bakery"
new_repo "$checkout" main
write_handoff "$store" bakery oven-schedule "" "" "" ""
list "$store" "$checkout"
check "old file: found by its folder" has_line "  found-by: folder name; the file has no **Project:** header"
check "old file: the date is labelled as the file's time" \
	has_line "  written: $today, today (file time; no usable **Written:** header)"
check "old file: missing fields are flagged" has_text "flag: header-incomplete no **Repo:** path"
check "old file: action is ask" has_line "action: ask"
# Fields without backticks are still read.
printf '# Continue\n\n**Project:** bakery\n**Repo:** %s   **Branch:** fix/proofing-time   **Written:** %s\n' \
	"$checkout" "$today" >"$store/bakery/proofing.md"
list "$store" "$checkout" proofing
check "old file: a value without backticks is read" block_has proofing "recorded-branch: fix/proofing-time"
check "old file: its path still matches" block_has proofing "reason: repo-path +40"

# --- outside a git repository ------------------------------------------------------------------
store="$work/store-plain"
plain="$work/field-notes"
mkdir -p "$plain"
write_handoff "$store" field-notes survey-draft field-notes "$plain" none "$today"
list "$store" "$plain"
check "no git: exits 0" [ "$status" -eq 0 ]
check "no git: the folder name is the project" has_line "project: field-notes"
check "no git: the branch line says so" has_line "branch: none (not a git repository)"
check "no git: the handoff is found" has_line "proposed: 1 survey-draft"
check "no git: action is load" has_line "action: load"
check "no git: no pull-request check is attempted" has_text "pr-check: not-needed"

# --- no handoff at all ---------------------------------------------------------------------------
list "$work/store-that-does-not-exist" "$plain"
check "empty: exits 0" [ "$status" -eq 0 ]
check "empty: a missing store is said to be missing" has_line "store: $work/store-that-does-not-exist (does not exist)"
check "empty: confidence is none" has_line "confidence: none"
check "empty: action is none" has_line "action: none"
check "empty: no candidates" has_line "candidates: 0"
check "empty: says the handoff skill creates the store" has_text "note: the store does not exist; the handoff skill creates it"

# --- where the store is -----------------------------------------------------------------------------
checkout="$work/parcel-tracker"
write_handoff "$work/config/handoffs" parcel-tracker from-config-dir parcel-tracker "$checkout" fix/label-printer "$today"
write_handoff "$HOME/.claude/handoffs" parcel-tracker from-home parcel-tracker "$checkout" fix/label-printer "$today"
(cd "$checkout" && PICKUP_GH="$no_gh" sh "$script") >"$work/out" 2>&1
check "store: the default is under the home .claude" has_line "store: $HOME/.claude/handoffs"
check "store: the default store is read" has_line "proposed: 1 from-home"
(cd "$checkout" && CLAUDE_CONFIG_DIR="$work/config" PICKUP_GH="$no_gh" sh "$script") >"$work/out" 2>&1
check "store: CLAUDE_CONFIG_DIR moves it" has_line "proposed: 1 from-config-dir"
(cd "$checkout" && CLAUDE_CONFIG_DIR="$work/config" HANDOFF_DIR="$work/store-single" PICKUP_GH="$no_gh" \
	sh "$script") >"$work/out" 2>&1
check "store: HANDOFF_DIR overrides both" has_line "proposed: 1 fix-label-printer"
check "store: the override is printed" has_line "store: $work/store-single"

# --- the pull-request check -----------------------------------------------------------------------
store="$work/store-single"
checkout="$work/parcel-tracker"
gh=$no_gh
list "$store" "$checkout"
check "gh absent: the listing still works" has_line "proposed: 1 fix-label-printer"
check "gh absent: the check is reported unavailable" has_line "pr-check: unavailable (the GitHub CLI was not found)"
check "gh absent: the state is unknown, not none" has_line "  pr: unknown"
check "gh absent: no pull-request flag" lacks_text "flag: pr-"
check "gh absent: action is still load" has_line "action: load"

gh=$fake_gh
FAKE_GH_FAIL=1
export FAKE_GH_FAIL
list "$store" "$checkout"
check "gh failing: the check is reported unavailable" has_text "pr-check: unavailable (the GitHub CLI failed"
check "gh failing: the state is unknown" has_line "  pr: unknown"
check "gh failing: action is still load" has_line "action: load"
FAKE_GH_FAIL=0

FAKE_GH_ROWS=$(printf 'MERGED\t41\tfix/label-printer\nOPEN\t40\tfix/other\n')
export FAKE_GH_ROWS
list "$store" "$checkout"
check "gh: the check is reported as done" has_line "pr-check: checked"
check "gh: a merged pull request is flagged" has_text "flag: pr-merged the pull request for fix/label-printer is merged (#41)"
check "gh: a merged stream is still listed" has_line "proposed: 1 fix-label-printer"
check "gh: a merged stream has to be asked about" has_line "action: ask"

FAKE_GH_ROWS=$(printf 'CLOSED\t41\tfix/label-printer\n')
list "$store" "$checkout"
check "gh: a closed pull request is flagged" has_text "flag: pr-closed"

FAKE_GH_ROWS=$(printf 'OPEN\t52\tfix/label-printer\nMERGED\t41\tfix/label-printer\n')
list "$store" "$checkout"
check "gh: an open pull request is not a flag" has_line "  pr: open #52"
check "gh: with an open pull request it loads" has_line "action: load"

FAKE_GH_ROWS=$(printf 'MERGED\t7\tfix/something-else\n')
list "$store" "$checkout"
check "gh: no pull request for the branch is not a flag" has_line "  pr: none-found"

# A GitHub CLI that never answers is stopped, and the listing still comes.
slow_gh="$work/bin/slow-gh"
printf '#!/bin/sh\nexec sleep 30\n' >"$slow_gh"
chmod +x "$slow_gh"
gh=$no_gh
list "$store" "$checkout"
quiet_lines=$(grep -c . "$work/out")
(cd "$checkout" && HANDOFF_DIR="$store" PICKUP_GH="$slow_gh" PICKUP_GH_WAIT=1 sh "$script") >"$work/out" 2>&1
check "gh hanging: the check is given up on" has_text "pr-check: unavailable (the GitHub CLI failed"
check "gh hanging: the listing still works" has_line "proposed: 1 fix-label-printer"
check "gh hanging: stopping it prints nothing extra" [ "$(grep -c . "$work/out")" -eq "$quiet_lines" ]

# A pull request finished before the handoff was written belongs to earlier
# work on a branch name that was used again.
gh=$fake_gh
FAKE_GH_ROWS=$(printf 'MERGED\t41\tfix/label-printer\t%s\n' "$long_ago")
list "$store" "$checkout"
check "gh: an earlier pull request on a reused branch name is not a flag" has_line "  pr: earlier #41"
check "gh: with only an earlier pull request it loads" has_line "action: load"
FAKE_GH_ROWS=$(printf 'MERGED\t41\tfix/label-printer\t%s\n' "$today")
list "$store" "$checkout"
check "gh: a pull request merged since the handoff is flagged" has_text "flag: pr-merged"

# Pull requests are this repository's. They apply to a handoff written in
# another worktree of it, and never to one written in another repository.
FAKE_GH_ROWS=$(printf 'MERGED\t9\tfeat/press-schedule\n')
list "$work/store-worktree" "$work/vineyard"
check "gh: a handoff from another worktree is checked" has_text "flag: pr-merged"
new_repo "$work/other-repository" feat/press-schedule
write_handoff "$work/store-other-repo" vineyard same-branch-name vineyard "$work/other-repository" feat/press-schedule "$today"
list "$work/store-other-repo" "$work/vineyard"
check "gh: a handoff from another repository is not checked" \
	has_line "  pr: not-checked (recorded in another repository)"
check "gh: and gets no pull-request flag" lacks_text "flag: pr-"
unset FAKE_GH_ROWS FAKE_GH_FAIL
gh=$no_gh

# --- usage -----------------------------------------------------------------------------------------
list "$store" "$checkout" --help
check "usage: --help exits 0" [ "$status" -eq 0 ]
check "usage: --help prints usage" has_text "Usage: list-handoffs.sh"
list "$store" "$checkout" --bogus
check "usage: an unknown option exits 2" [ "$status" -eq 2 ]
list "$store" "$checkout" one two
check "usage: two names exit 2" [ "$status" -eq 2 ]

# --- the script runs under every POSIX shell on this machine ------------------------------------
store="$work/store-clear"
checkout="$work/orchard"
list "$store" "$checkout"
cp "$work/out" "$work/expected"
for shell in dash bash ksh zsh; do
	command -v "$shell" >/dev/null 2>&1 || continue
	(cd "$checkout" && HANDOFF_DIR="$store" PICKUP_GH="$no_gh" "$shell" "$script") >"$work/out" 2>&1
	check "shells: $shell prints the same listing" cmp -s "$work/out" "$work/expected"
done

finish list-handoffs
