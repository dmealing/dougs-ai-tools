# pickup

> **Experimental.** The selection rules and the printed format may change. Tell us when it picks wrongly.

A Claude Code skill that resumes work from a handoff without you pasting a path. It finds the handoff for the checkout you are in and **shows which one it chose, why, and what else it could have chosen, before it reads anything**.

It requires the [handoff](../handoff/) skill, which writes the files this one reads. The plugin declares that dependency, so `claude plugin install pickup@dougs-ai-tools` brings the handoff plugin with it. The install script does not check it: with pickup installed alone that way, `/pickup` simply finds nothing to pick up.

## The problem

The handoff skill ends a session by printing the path of one Markdown file. To continue, you start a new session and paste that path. Finding the file for you sounds simple and is not: one project has several streams of work live at once, in several checkouts, and many handoffs record a branch such as `main` that says nothing about which stream they belong to.

A tool that picks silently is right most of the time and wrong without warning. After one wrong pick you stop trusting it, and pasting the path is faster than checking its work. So this skill never picks silently. Every pickup states the chosen file, the evidence for it, anything doubtful about it, and the alternatives. It loads without a question only when the evidence is unambiguous and nothing is flagged; otherwise it asks you to choose.

## What the skill does

You type `/pickup`, or `/pickup <name>` to name the stream. The agent then:

1. **Runs `list-handoffs.sh`**, a read-only script that finds this project's live handoffs and weighs each one.
2. **Shows you the choice** before reading any handoff: the file, the reasons, the flags and the alternatives.
3. **Loads it without asking** only when the script reports one unflagged, unambiguous choice. Otherwise it lists the candidates and you choose by number or by name. It never adopts another stream on its own.
4. **Verifies the handoff against the checkout**, reports what has drifted, runs the handoff's start step and begins the work.
5. **Offers to archive** the handoff to `done/` when the stream is finished.

It starts only on `/pickup` or an explicit request to resume from a handoff. A bare "continue" does not start it.

Requirements: Claude Code, the handoff skill, and a POSIX shell with the usual tools (`sed`, `awk`, `sort`, `stat`), on macOS or Linux. `git` and `gh` are optional: outside a git repository the folder name identifies the project, and without a working `gh` the pull-request check is skipped and reported as skipped.

## Install

Pick one. With the install script, install the handoff skill the same way.

### As a Claude Code plugin

```sh
claude plugin marketplace add dmealing/dougs-ai-tools
claude plugin install pickup@dougs-ai-tools
```

The handoff plugin is installed with it, as a declared dependency. The skill is allowed to run its own read-only listing script without a permission prompt; that is the only command it pre-approves.

Inside a session, the same steps are `/plugin marketplace add dmealing/dougs-ai-tools` and `/plugin install pickup@dougs-ai-tools`.

Plugin skills carry the plugin's name as a prefix, so the command is `/pickup:pickup`. Asking in words ("pick up the handoff") works too.

### With the install script

```sh
git clone https://github.com/dmealing/dougs-ai-tools.git
sh dougs-ai-tools/handoff/install.sh
sh dougs-ai-tools/pickup/install.sh
```

This copies `SKILL.md` and `list-handoffs.sh` to `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills/pickup/`, and the command is `/pickup`. Run the script from the cloned repository: it uses code in the repository's `lib/` folder.

| Command | Effect |
|---|---|
| `sh install.sh` | Install. Does nothing if the same version is already there. Refuses to overwrite a file that differs. |
| `sh install.sh --force` | Install, replacing a file that differs. |
| `sh install.sh --uninstall` | Remove the skill. Refuses if an installed file differs from the shipped one. |
| `sh install.sh --uninstall --force` | Remove the skill even if it was modified. |

A refusal changes nothing: no file is copied or removed. Install it one way, not both, or the skill is listed twice.

## How it chooses

### Which files are candidates

The store and the project are found by the handoff skill's own rule, with the same environment variables (`HANDOFF_DIR`, `CLAUDE_CONFIG_DIR`). The script contains that rule's lines unchanged, and a test fails if the two drift apart. For a bare clone with its working trees beside it, the project is named by the bare directory's holder (`.bare` or `.git` takes its parent's name, `name.git` becomes `name`), as in the handoff skill.

- **Only live handoffs.** The top level of each project folder is read. `done/` is never read.
- **The project named inside the file decides.** A handoff is a candidate when its `**Project:**` header equals this project's name, whichever folder it sits in. A file filed under the wrong folder is still found, and the listing says where it sits.
- **The folder name is used only for a file with no `**Project:**` header**, and then only on an exact match.
- **No prefix matching.** A project named `widget` never picks up handoffs from `widget-shop`.
- A file in this project's folder whose header names a different project is not a candidate. It is printed on a `skipped:` line.
- **Handoffs filed under the old name of a bare-clone layout are still found.** Before the bare-clone rule, such a repository was filed under the bare directory's own name (for example `.bare`), shared by every repository laid out that way. A file whose project (or, without a header, folder) is that old name is a candidate when its recorded `**Repo:**` is a checkout of this repository. When the recorded checkout cannot be checked (it was removed, or the file has no `**Repo:**`), the file is kept and flagged `legacy-project`. A file recorded in a different repository is not offered.

### How candidates are weighed

Each candidate gets points for evidence that it belongs to the work in front of you. Every point is printed with its reason.

| Reason | Points | Meaning |
|---|---|---|
| `name-exact` | +200 | The name you gave is the stream's name. Upper case, `/` and spaces are normalised first, so `Fix/Label Printer` matches `fix-label-printer`. |
| `name-partial` | +100 | The name you gave is part of the stream's name. |
| `repo-path` | +40 | The handoff's recorded `**Repo:**` path is this checkout. Symbolic links are resolved on both sides. |
| `branch` | +40 | The handoff's recorded `**Branch:**` is the branch checked out here, and that branch is not a default branch and not a detached HEAD. |

A name you give outranks everything else combined: you said which stream you meant.

Two kinds of match are printed as **weak** evidence and add no points, so neither can decide a choice:

| Weak | Meaning |
|---|---|
| `default-branch` | The handoff and this checkout are both on the same default branch. Many streams are written from a default branch, so it identifies none of them. Default branches are `main`, `master`, `trunk`, `develop`, the branch the `origin` remote calls its default when git knows it, and any name in `PICKUP_DEFAULT_BRANCHES`. |
| `detached` | Both are on a detached HEAD. The line says whether it is the same commit; it is weak either way. When the commit differs, the handoff is also flagged `different-commit`. |
| `commit` | The handoff recorded a `**Commit:**`. The line says how this checkout stands to it: at the same commit, N commits ahead, N commits behind, diverged from it, or the commit is not in this repository. Handoffs from before that header existed print no such line, and that is not a flag. |

**Recency** orders candidates that have the same points, newest first. It never breaks a tie: equal points are reported as `ambiguous`. The date is the handoff's `**Written:**` value. The file's modification time is used only when that header is missing or unreadable, and the listing labels it as file time, so a copied or touched file does not look new.

### Confidence

| Confidence | When | What happens |
|---|---|---|
| `single` | Exactly one live handoff for the project (and it matches the name, if you gave one). | Loaded without a question if it has no flag. |
| `clear` | Several, and one has more points than every other. | Loaded without a question if it has no flag. |
| `ambiguous` | Several, and the best ones have equal points, including zero. | You choose. |
| `none` | No live handoff, or none matches the name you gave. | Nothing is loaded. |

The script turns this into one `action:` line so the decision is not left to interpretation: `load` (`single` or `clear`, and the proposed handoff has no flag), `ask`, or `none`. Even on `load`, the agent states the choice in a line or two before it reads the file.

### Flags

A flag never hides a handoff. It is printed with the candidate, and a flag on the proposed handoff turns `load` into `ask`.

| Flag | Meaning |
|---|---|
| `stale` | Written more than `PICKUP_STALE_DAYS` days ago (default 14). |
| `repo-missing` | The recorded repository path no longer exists, for example a removed worktree. |
| `branch-missing` | The recorded branch exists neither locally nor as a remote-tracking branch, in this repository or in the recorded one. A default branch that was renamed away is flagged the same way. |
| `different-checkout` | The recorded repository path exists and is not this checkout. The stream may belong to another worktree or clone. |
| `different-branch` | The handoff was written on a named branch that is not the one checked out here. |
| `different-commit` | The handoff was written on a detached HEAD at one commit, and this checkout is detached at another. A detached HEAD names no stream, so a matching path alone may be a checkout folder that was reused for other work. |
| `pr-merged` | The pull request for the recorded branch is merged. The work may be finished; the handoff may also still hold follow-up work. |
| `pr-closed` | The pull request for the recorded branch was closed without merging. |
| `legacy-project` | The file is filed under the old project name of a bare-clone layout and its recorded checkout cannot be checked, so it may belong to another repository. |
| `header-incomplete` | The file lacks a usable `**Repo:**`, `**Branch:**` or `**Written:**` value. |

The pull-request flags need `gh`, installed and working, in a repository hosted on GitHub. One call is made, for the 200 most recent pull requests of the repository you are in. When it cannot be made, the listing says `pr-check: unavailable` and each candidate shows `pr: unknown`, which is not the same as having no pull request. Three cases are never a flag:

- an open pull request;
- a pull request that was merged or closed before the handoff was written (`pr: earlier #N`): it belongs to older work on a branch name that was used again;
- a handoff whose recorded checkout belongs to a different repository (`pr: not-checked`): this repository's pull requests say nothing about that one's branches.

## What the script prints

`list-handoffs.sh [name]` prints plain lines, each `key: value`. The run comes first, then one block per candidate, best first. In a checkout of `parcel-tracker` on branch `fix/label-printer`, with the store set to `/srv/handoffs`:

```
pickup: format 1
store: /srv/handoffs
project: parcel-tracker
checkout: /srv/checkouts/parcel-tracker
branch: fix/label-printer (named branch)
name: (not given)
stale-after-days: 14
pr-check: checked
candidates: 3
archived: 12
confidence: clear
proposed: 1 fix-label-printer
action: load

[1] fix-label-printer
  path: /srv/handoffs/parcel-tracker/fix-label-printer.md
  written: 2025-03-14, 2 day(s) ago
  recorded-repo: /srv/checkouts/parcel-tracker
  recorded-branch: fix/label-printer
  found-by: project header
  pr: open #52
  score: 80
  reason: repo-path +40 the recorded repository path is this checkout
  reason: branch +40 the recorded branch is the branch checked out here
  flag: none

[2] search-index
  path: /srv/handoffs/parcel-tracker/search-index.md
  written: 2025-03-13, 3 day(s) ago
  recorded-repo: /srv/checkouts/parcel-tracker-search
  recorded-branch: feat/search-index
  found-by: project header
  pr: none-found
  score: 0
  reason: none
  flag: different-checkout the recorded repository path exists and is not this checkout
  flag: different-branch recorded on feat/search-index; here is fix/label-printer

[3] billing-export
  path: /srv/handoffs/parcel-tracker/billing-export.md
  written: 2025-01-20, 55 day(s) ago
  recorded-repo: /srv/checkouts/parcel-tracker-old
  recorded-branch: main
  found-by: project header
  pr: not-applicable
  score: 0
  reason: none
  flag: stale written 55 days ago, limit 14
  flag: repo-missing the recorded repository path no longer exists
```

The agent turns that into:

> Picking up **fix-label-printer** (`/srv/handoffs/parcel-tracker/fix-label-printer.md`): written 2 days ago in this checkout, on the branch checked out here. No flags. Two other live handoffs: **search-index** (another checkout and branch) and **billing-export** (55 days old, its checkout is gone).

### The lines

| Line | Value |
|---|---|
| `pickup: format 1` | The format's version. It changes when an existing line's meaning changes or a line goes away. Adding a new `weak:` or `flag:` name, as `commit`, `different-commit` and `legacy-project` were added, does not change it. |
| `store:` | The store that was read, with `(does not exist)` when it is missing. |
| `project:` | The project name. |
| `checkout:` | The top of the current checkout, or the current directory outside git. |
| `branch:` | The current branch, and its kind: `named branch`, `default branch`, `detached HEAD` or `not a git repository`. |
| `name:` | The name argument, or `(not given)`. |
| `stale-after-days:` | The age limit in force. |
| `pr-check:` | `checked`, `unavailable (why)` or `not-needed (why)`. |
| `candidates:` | How many candidate blocks follow. |
| `archived:` | How many handoffs are in the project's `done/` folder. They are counted, never read. |
| `confidence:` | `single`, `clear`, `ambiguous` or `none`. |
| `proposed:` | `1 <stream>`: the proposal is block `[1]`. Or `none`. |
| `action:` | `load`, `ask` or `none`. |
| `note:` | Zero or more lines that explain the result: a tie, a name that matched nothing, or a store that does not exist yet. |
| `skipped:` | Zero or more files in this project's folder whose header names another project. |

Each candidate block starts with `[rank] stream` and holds, indented by two spaces: `path:` (the exact file), `written:` (date, age, and a file-time label when it applies), `recorded-repo:`, `recorded-branch:`, `found-by:`, `pr:` (`open #N`, `merged #N`, `closed #N`, `earlier #N`, `none-found`, `unknown`, `not-checked (why)` or `not-applicable`), `score:`, then one or more `reason:` and `weak:` lines (`reason: none` when there are neither) and one or more `flag:` lines (`flag: none` when there are none).

The script exits 0 whenever it printed a listing, including an empty one, and 2 on a usage error.

### Settings

| Variable | Effect |
|---|---|
| `HANDOFF_DIR` | Replaces the default store, as in the handoff skill. |
| `CLAUDE_CONFIG_DIR` | Moves the default store to `$CLAUDE_CONFIG_DIR/handoffs`, as in the handoff skill. |
| `PICKUP_STALE_DAYS` | Days after which a handoff is flagged `stale`. Default 14. |
| `PICKUP_DEFAULT_BRANCHES` | Extra branch names to treat as default branches, separated by spaces. |
| `PICKUP_GH` | The GitHub CLI command to run. Default `gh`. Set it to a name that does not exist to turn the pull-request check off. |
| `PICKUP_GH_WAIT` | Seconds to wait for the GitHub CLI before giving up on it. Default 15. |

You can run the script yourself at any time to see what a pickup would choose:

```sh
sh ~/.claude/skills/pickup/list-handoffs.sh
```

## Limits

- **A handoff written on a default branch cannot be told apart from its siblings without a name.** Two streams handed off from the same checkout on `main` have the same evidence. The script reports `ambiguous` and the agent asks; `/pickup <name>` settles it. Handing off from a branch named for the work avoids the question.
- **A detached HEAD is the same.** It identifies a commit, not a stream.
- **It trusts the header.** A handoff whose `**Repo:**` or `**Branch:**` line was written wrongly is weighed wrongly. The listing prints what was recorded so you can see it.
- **It does not know which session you just left.** It reads no session transcripts and no other agent internals, so "the handoff I wrote a minute ago" is not evidence. The checkout, the branch and the name are.
- **The pull-request check covers GitHub only**, needs `gh`, and looks at the 200 most recent pull requests. Squash-merged work on other hosts is not detected.
- **`pr-merged` does not mean finished**, and nothing is archived or deleted automatically. Old handoffs stay listed, flagged `stale`, until you archive them.
- **Two repositories whose folders share a name share a project**, because that is the handoff skill's rule. Their handoffs appear together; the recorded repository path tells them apart.
- **macOS is supported but tested by construction, not on a Mac in this repository's own test run**: the script is POSIX sh, the tests run it under every POSIX shell they find, and a check rejects the GNU-only constructs that stock macOS lacks.

## Tests

```sh
sh pickup/tests/run.sh
```

The path above is from the repository root; the script itself runs from anywhere. It builds throwaway stores and git repositories to test `list-handoffs.sh`, tests `install.sh` against a throwaway directory, checks the shipped files for absolute home paths and for shell that stock macOS lacks, and runs `shellcheck` when it is installed. Nothing reads the real store or the network. `sh tests/run.sh` runs every tool's tests.

## Licence

Apache-2.0. See [LICENSE](../LICENSE).
