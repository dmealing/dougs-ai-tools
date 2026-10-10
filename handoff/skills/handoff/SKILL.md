---
name: handoff
description: Use ONLY when the user explicitly asks to hand work to a new session — "/handoff", "hand this off", "write a prompt to continue in a fresh session". Writes exactly one file and ends the session's work. Never invoke this on your own initiative to wrap up, summarize, or because context is filling.
---

# Handoff

## When to write one

**A handoff is written only when the user asks for one.** Only these open the gate:

- `/handoff`, with or without words after it (Part 7 says what the words are for)
- "hand this off", "write a prompt to continue", "give me something to start a fresh session with"
- a direct answer of *yes* to an offer you made

**Nothing else does.** A context notice from any tool, a percentage crossing 40% or 70%, a finished pull request or test run, "that's done" or "nice", and your own sense that this is a clean break are all facts or acknowledgements, never a request. A notice informs the **user**; it does not ask you to write a file. In the author's own use, the sense of a clean break often fired while most of the window was still free.

**When you believe a boundary has arrived, you may offer one, in a single line, and then you stop:**

> Pull request #42 is merged and the tree is clean. Clean break if you want it — say the word and I'll write the handoff.

Then **do nothing**. Do not draft it "so it's ready", do not write a scratch file, do not start the verification commands. The user says yes, or they don't.

---

A handoff carries **what the next session cannot recover on its own**: above all *what was already tried and failed*, and *why* things are the way they are. It is loaded once, so `CLAUDE.md`-style rules about dilution do not apply.

**Where the file goes:** `~/.claude/handoffs/<project>/<stream>.md` by default (Part 3 has the exact rule). The `HANDOFF_DIR` environment variable replaces `~/.claude/handoffs` with another directory, for example `/tmp`, which is wiped on restart.

**Works with:** a shell. `git` and `gh` are used when present. The `pickup` skill reads these files; nothing here depends on it.

**More on demand:** `${CLAUDE_SKILL_DIR}/reference.md` holds a worked example of a finished handoff and the list of common mistakes. Read it when a section's shape is unclear. It adds no rule.

# PART 1 — THE GATE

**Three questions. All three must pass, or you write nothing.**

## Gate 1 — Did the user ask?

The rule at the top decides. If the user did not ask, write nothing.

## Gate 2 — Is anything in flight that dies with this session?

A handoff is worthless if ending the session destroys the work it describes. **Classify every running thing before you write.**

**Re-attachable** (a fresh session can pick it up from an identifier): a hosted CI run (`gh run view <id>`), checks on a pull request (`gh pr checks <number>`), or a job on a remote host or queue that outlives this terminal. The handoff is allowed, and `**Start:**` MUST be the re-attach command.

**Not re-attachable** (dies when the session ends): a subagent, monitor or watcher this session started; a background shell job, local build, server or test run you started; an unfinished multi-step edit. The handoff is **refused**.

**On a refusal, say exactly what is running and offer the two real options — write no file:**

> Not a clean break. The integration suite is on test 212 of 340 in a local process; it dies when this session ends and there is no run id to re-attach to. Want me to wait for it and then write the handoff, or stop it and hand off without the result?

Never write the file and flag the problem in it. The user's decision comes first.

## Gate 3 — Is this the session's last act?

If you intend to do anything after the handoff, you are not at a handoff. `/handoff and then fix the retry bug` does **not** mean *write the file, then fix the bug*: the bug is the next session's first task, written into `## Still to do`. Is a todo still open that you planned to finish? Finish it first and then write, or write it into `## Still to do`. There is no third option.

# PART 2 — THE TERMINAL RULE

**One invocation, one file, one write, and the path is the last thing you say.** End your message with the absolute path on its own line and the `wc -lm` counts, then stop: no further tool calls. In the author's own use, sessions that kept working let the path scroll out of view and the user lost the file.

Do **not** write a second handoff on your own; more happening after the first means Gate 3 was broken. If the user asks again after further work, rewrite fresh (Part 4) and stop again. One stream, one file, never two.

# PART 3 — WHERE IT GOES, AND THE LIFECYCLE

```
<root>/<project>/<stream>.md   <- LIVE. Nothing else lives here.
<root>/<project>/done/         <- archived: finished streams, and earlier versions of rewritten ones.
```

`<root>` is `$HANDOFF_DIR` when set, otherwise `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/handoffs`. It sits outside every repository, so a handoff cannot be committed by accident. **Top level means live:** listing `<project>/` returns only streams a fresh session could pick up.

## `<project>` — one rule

`<project>` is the directory name of the repository's main working tree, so every worktree of one repository shares one folder (a bare clone is named by what holds it). Outside git it is the current directory's name. Resolve it with this, which runs unchanged on macOS and Linux:

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

Do not derive the name any other way — not from the remote URL, the branch or the worktree you are in. A handoff filed under a different name is a handoff nobody finds.

## `<stream>` — the thread of work, not the project

Several streams run in one repository at once, and one file per project would overwrite all but the last. Name the file after *this thread of work*: the branch name, the issue number or the feature. Lower case, with `/` and spaces replaced by `-`: branch `fix/rounding-on-refund` becomes `fix-rounding-on-refund.md`.

## The header is machine-read — keep it exact

The companion `pickup` skill parses these lines to find the right handoff:

```markdown
**Project:** `<project>`
**Repo:** `<absolute path of THIS checkout>`   **Branch:** `<branch>`   **Written:** <YYYY-MM-DD>
**Commit:** `<short hash of the current commit>`
**Start:** <first command>
```

- `**Project:**` is the resolved name above, in backticks; it equals the folder the file sits in.
- `**Repo:**` is the absolute path of the checkout you worked in (the worktree, not the main working tree), in backticks.
- `**Branch:**` is `git branch --show-current`, in backticks, first after the marker; extra words after it are fine, prose in place of it is not. Detached HEAD: `` `detached@<short-sha>` ``. Outside git: `` `none` ``.
- `**Written:**` is `date +%Y-%m-%d`.
- `**Commit:**` is `git rev-parse --short HEAD`, in backticks, on its own line. Outside git, or with no commit yet, leave the line out.

## Archiving a finished stream

When the work a handoff describes is **done** — merged, shipped, closed, abandoned — it gets archived, not another handoff:

```bash
mkdir -p "$dir/done"
target="$dir/done/<stream>.md"
# A reused stream name must not overwrite an earlier archive.
if [ -e "$target" ]; then target="$dir/done/<stream>-$(date +%Y%m%d-%H%M%S).md"; fi
mv "$dir/<stream>.md" "$target"
```

Say so in one line: `Stream finished — archived to done/, nothing to pick up.` Do **not** write a final handoff whose content is "everything is done", and do **not** invent an in-file marker (`## CONSUMED`, a strikethrough banner). `done/` is the marker.

# PART 4 — REWRITE FRESH. NEVER EDIT.

**Use `Write`. Never `Edit` a handoff file.** A continuing stream can run ten or twenty handoffs deep, and editing carries the old file forward by default, dropping only what you happened to notice. That is how a `## Still to do` item finished three sessions ago survives to waste the next session's time.

1. **Read** the existing file for this stream, if there is one.
   - **Check it is yours.** Two repositories whose folders share a name share a `<project>` folder, and two branches can shorten to the same file name. If its `**Repo:**` is a checkout of a different repository, or its `**Branch:**` is a different branch that is still live, it is someone else's stream: pick a distinct file name for yours and say in one line that you did.
2. **Keep the previous version.** Before you write over it, copy it to `done/` under a timestamped name, so a rewrite that dropped something it should not have can be recovered:

   ```bash
   mkdir -p "$dir/done" && cp -p "$dir/<stream>.md" "$dir/done/<stream>-$(date +%Y%m%d-%H%M%S).md"
   ```

3. **Re-derive every line.** For each thing in the old file: *is this still true, today, verified this session?* Done → **drop it**, no strikethrough. Still true → carry it forward, rewritten. Unsure → verify it now, or cut it.
4. **`Write`** the new file over the same path.

**Dead ends are the exception that must survive.** A revert leaves no trace in git, so if you drop a dead end it is gone permanently and the next session re-runs your failure. Carry every dead end still in force, every time.

# PART 5 — VERIFY BEFORE YOU WRITE

You are writing when your context is most degraded, when confident fiction appears: tests that "pass" but were never re-run, descriptions twenty edits stale. Write from command output, not memory:

```bash
git status --short; git branch --show-current; git rev-parse --short HEAD
git log --oneline '@{u}..HEAD' 2>/dev/null   # unpushed commits; silent with no upstream
git stash list
if command -v gh >/dev/null 2>&1; then gh pr status 2>/dev/null | head -20; fi
```

Outside git, skip the `git` lines and describe the files directly. If you assert a test passes, you ran it this session. If you cannot verify a claim cheaply, cut it.

# PART 6 — THE RECIPE

Order is deliberate: blocking first, then what will waste the reader's time, then the work. Nothing load-bearing sits at the bottom.

**Size: whatever the gates admit.** In the author's own use a handoff ran from a few thousand characters to about ten thousand. That is neither a floor nor a ceiling.

**Leave out secrets:** keys, tokens, passwords and personal data. Say where a secret lives (the variable name, the vault entry, the file path) instead of what it is.

```markdown
# Continue — <project>: <stream>

**Project:** `<project>`
**Repo:** `<absolute path of THIS checkout>`   **Branch:** `<branch>`   **Written:** <YYYY-MM-DD>
**Commit:** `<short hash of HEAD; leave the line out outside git>`
**Start:** <the single first command, assuming a shell in the repo above.
           If something re-attachable is running, this IS the re-attach command.>
**Next session:** <only when the user said what it is for; otherwise leave the line out>

## Blocking
<what the user must decide before work can proceed, or "nothing".>

## Dead ends
<approaches tried that did NOT work, and why. THE HIGHEST-VALUE SECTION: a revert leaves no trace in git. Tie each to the open item it affects. Carry forward every one still in force.>

## What will mislead you
<a doc or issue body now false (name it), a known false alarm, a convention that differs from the default. Not "things we tried".>

## In flight
<uncommitted files, unpushed commits, a migration written but not applied, a CI run still going (id and re-attach command). Say what is ambiguous about each.>

## Still to do
<concrete remaining work: file, symbol or command per item. Nothing already finished.>

## Decisions and why
<rationale still load-bearing on the next session, including alternatives rejected.>

---
Re-verify anything above that you are about to act on, and report what has drifted.
```

## What earns a line

Keep an entry only if the next session cannot get it in one command (why an approach was abandoned, why a live decision was made, a doc that is now stale, a false alarm already diagnosed) **and** someone holding only that line would avoid the mistake we made. `reference.md` has the full test. No size target overrides it, in either direction.

# PART 7 — WHAT THE NEXT SESSION IS FOR

Words after `/handoff` say what the next session will do, for example `/handoff next: add the retry ceiling setting` or `/handoff review only, no edits`. They are not a task for this session (Gate 3). Without them, write the handoff for the stream as a whole.

With them:

- put the line in the header as `**Next session:** <their words, shortened>`;
- open `## Still to do` with the work that purpose needs, and cut recoverable detail that only serves other work;
- **do not** drop a dead end, a misleading signal or an in-flight item that still holds because it is outside the purpose. Keep it, in one line.

If the words do not describe a next session (a question, a complaint about this one), ask what they mean before writing.

# PART 8 — CLOSING OUT

Your final message contains the **absolute path on its own line**, plus the counts from `wc -lm "$dir/<stream>.md"` (`-m` counts characters). If you kept a previous version, say where in one line. Tell the user how to resume: start a new session in the same repository and paste the path, for example `Read <path> and continue from it`. If the `pickup` skill is installed, `/pickup <stream>` finds the file without the path. Then stop. See Part 2.

---

# Red flags

- Something is running that has no run id, and you are writing anyway
- You are writing a second handoff this session, or using `Edit` on one, or writing over one you did not copy to `done/`
- You are about to do anything at all after printing the path
- `## Dead ends` is empty after a session that hit real obstacles
- You asserted a test result or branch state you did not check this session
