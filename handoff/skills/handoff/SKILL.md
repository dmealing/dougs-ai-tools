---
name: handoff
description: Use ONLY when the user explicitly asks to hand work to a new session — "/handoff", "hand this off", "write a prompt to continue in a fresh session". Writes exactly one file and ends the session's work. Never invoke this on your own initiative to wrap up, summarize, or because context is filling.
---

# Handoff

Write one file that lets a fresh session continue this work. It carries what the next session cannot recover by itself: what was tried and failed, why things are the way they are, and what is still running. A fresh session reads it once, so every line should carry one of those things.

**A handoff is written only when the user asks for one:** `/handoff` (words after it are covered under "What the next session is for"), "hand this off", "write a prompt to continue", or a yes to an offer you made. A context-usage notice, a finished pull request or test run, "that's done", or your own sense of a clean break is not a request. If you think a boundary has arrived, offer in one line ("Clean break if you want it: say the word and I'll write the handoff.") and do nothing more until the user answers.

`${CLAUDE_SKILL_DIR}/reference.md` has a worked example and common mistakes. Read it when a section's shape is unclear.

# PART 1 — Before you write

## Gate 1 — The user asked

As above. If not, write nothing.

## Gate 2 — Nothing running dies with this session

Classify every running thing:

- **Re-attachable** from an identifier: a hosted CI run (`gh run view <id>`), pull request checks (`gh pr checks <number>`), a job on a remote host or queue. Write the handoff, with the re-attach command as `**Start:**`.
- **Not re-attachable**: a subagent, monitor or background shell this session started, a local build, server or test run, an unfinished multi-step edit. Write no file. Say what is running and offer the choice: wait for it and then write, or stop it and hand off without the result. Do not write the file with a warning inside; the user decides first.

## Gate 3 — The handoff is this session's last act

Anything you mean to do after it belongs in `## Still to do`. `/handoff and then fix the retry bug` means the bug is the next session's first task. Finish an open todo first, or write it down.

After writing, end with the absolute path on its own line and the `wc -lm` counts, and make no further tool calls: the path is how the user finds the file, and later output scrolls it away. One stream, one file. If the user asks again after more work, rewrite it fresh.

# PART 2 — Where it goes

```
<root>/<project>/<stream>.md   <- live handoffs only
<root>/<project>/done/         <- finished streams and earlier versions
```

`<root>` sits outside every repository, so a handoff cannot be committed by accident:

```bash
main=$(git worktree list --porcelain 2>/dev/null | sed -n '1s/^worktree //p')
bare=$(git worktree list --porcelain 2>/dev/null | sed -n '2s/^bare$/yes/p')
project=$(basename "${main:-$PWD}")
if [ -n "$bare" ]; then case "$project" in .bare | .git) project=$(basename "$(dirname "$main")") ;; *.git) project=${project%.git} ;; esac; fi
root="${HANDOFF_DIR:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/handoffs}"
dir="$root/$project"
mkdir -p "$dir"
echo "$dir"
```

Use this rule and no other (not the remote URL, branch or worktree name): every worktree of a repository then shares one folder, and `pickup` looks only there.

`<stream>` names this thread of work, not the project: the branch, issue or feature, lower case, with `/` and spaces turned into `-` (`fix/rounding-on-refund` becomes `fix-rounding-on-refund.md`). Several streams can be live in one repository.

When the work is finished (merged, shipped, closed or abandoned), archive the file instead of writing a final handoff, and say so in one line:

```bash
mkdir -p "$dir/done"
target="$dir/done/<stream>.md"
# A reused stream name must not overwrite an earlier archive.
if [ -e "$target" ]; then target="$dir/done/<stream>-$(date +%Y%m%d-%H%M%S).md"; fi
mv "$dir/<stream>.md" "$target"
```

# PART 3 — Rewrite, do not edit

Use `Write`, not `Edit`: an edited handoff carries finished items forward into the next session.

1. Read the existing file for this stream, if any. If its `**Repo:**` is another repository, or its `**Branch:**` is another live branch, it is someone else's stream: use a different file name and say so.
2. Keep the previous version:

   ```bash
   mkdir -p "$dir/done" && cp -p "$dir/<stream>.md" "$dir/done/<stream>-$(date +%Y%m%d-%H%M%S).md"
   ```

3. Re-check every line against this session. Drop what is done; verify or cut what you are unsure of. Carry forward every dead end still in force: a revert leaves no trace in git, so a dropped dead end gets re-run.

# PART 4 — Write from command output

Write from what these print, not from memory; this late in a session, recall is least reliable:

```bash
git status --short; git branch --show-current; git rev-parse --short HEAD
git log --oneline '@{u}..HEAD' 2>/dev/null   # unpushed commits; silent with no upstream
git stash list
if command -v gh >/dev/null 2>&1; then gh pr status 2>/dev/null | head -20; fi
```

Outside git, describe the files directly. Claim a test passes only if you ran it this session.

# PART 5 — The file

Keep a line only if the next session cannot get it with one command and a reader holding only that line would avoid the mistake. Sections run from what blocks work to what wastes time to the work itself.

**Leave out secrets:** keys, tokens, passwords and personal data. Say where a secret lives (variable name, vault entry, file path), not what it is.

The header lines are parsed by the `pickup` skill, so keep their markers and backticks exact:

```markdown
# Continue — <project>: <stream>

**Project:** `<project>`
**Repo:** `<absolute path of THIS checkout>`   **Branch:** `<branch>`   **Written:** <YYYY-MM-DD>
**Commit:** `<short hash of HEAD; leave the line out outside git>`
**Start:** <the single first command, run from the repo above; the re-attach command if something is running>
**Next session:** <only when the user said what it is for; otherwise leave the line out>

## Blocking
<what the user must decide before work can go on, or "nothing">

## Dead ends
<approaches tried that failed, and why, each tied to the open item it affects>

## What will mislead you
<a doc or issue now false (name it), a known false alarm, a convention that differs from the default>

## In flight
<uncommitted files, unpushed commits, unapplied migrations, running CI (id and re-attach command), and what is ambiguous about each>

## Still to do
<remaining work, with a file, symbol or command per item>

## Decisions and why
<rationale the next session still depends on, including rejected alternatives>

---
Re-verify anything above that you are about to act on, and report what has drifted.
```

- `**Project:**` is the resolved name; it matches the folder.
- `**Repo:**` is the checkout you worked in (the worktree, not the main working tree).
- `**Branch:**` is `git branch --show-current`, first after the marker; `detached@<short-sha>` when detached, `none` outside git.
- `**Written:**` is `date +%Y-%m-%d`; `**Commit:**` is `git rev-parse --short HEAD`.

## What the next session is for

Words after `/handoff` (`/handoff next: add the retry ceiling setting`, `/handoff review only, no edits`) describe the next session, not work for this one. Put them in `**Next session:**` and open `## Still to do` with what that purpose needs. Cut recoverable detail that serves only other work, but **do not** drop a dead end, a misleading signal or an in-flight item because it lies outside the purpose: keep it in one line. If the words do not describe a next session, ask what they mean first.

# PART 6 — Close out

End with the absolute path on its own line and the counts from `wc -lm "$dir/<stream>.md"`. If you kept a previous version, say where. Tell the user to start a new session in the same repository and say `Read <path> and continue from it`, or `/pickup <stream>` if the `pickup` skill is installed. Then stop.
