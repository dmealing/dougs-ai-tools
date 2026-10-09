---
name: handoff
description: Use ONLY when the user explicitly asks to hand work to a new session — "/handoff", "hand this off", "write a prompt to continue in a fresh session". Writes exactly one file and ends the session's work. Never invoke this on your own initiative to wrap up, summarize, or because context is filling.
---

# Handoff

A handoff carries **what the next session cannot recover on its own** — above all *what was already tried and failed*, and *why* things are the way they are.

It is loaded **once** and replaces a session's worth of state. Rules for `CLAUDE.md`/`AGENTS.md` do not apply: those are paid every session, so dilution compounds. Do not carry an always-loaded-file instinct into it.

**Where the file goes:** `~/.claude/handoffs/<project>/<stream>.md` by default (Part 3 defines both names, and the exact rule). The `HANDOFF_DIR` environment variable replaces `~/.claude/handoffs` with a directory of the user's choice, for example `/tmp`. A temporary directory used that way is wiped on restart.

**Works with:** this skill is complete on its own and needs only a shell. `git` and `gh` are used when present and skipped when absent. The companion `pickup` skill in the same repository reads the files this one writes; nothing here depends on it.

---

# PART 1 — THE GATE

**Three questions. All three must pass, or you write nothing.** This part governs; everything after it is only *how* to write one once you are through.

## Gate 1 — Did the user ask?

Only these open the gate:

- `/handoff` (with or without extra words after it)
- "hand this off", "write a prompt to continue", "give me something to start a fresh session with"
- a direct answer of *yes* to an offer you made

**Nothing else does.** In particular, none of these are permission:

| Not permission | Why it feels like it |
|---|---|
| A warning or notice about context usage, from any tool | It informs the **user**. It does not ask you to write a file. |
| Context crossing 40%, 50%, 70%, any number | A percentage is a fact about the window, not a request. |
| Finishing a pull request, a task, a test run | Completing work is not the same as ending the session. |
| "That's done" / "nice" / "ok" | Acknowledgement, not instruction. |
| Your own sense that this is a clean break | Measured across a few hundred real sessions, that judgment regularly fired with less than 15% of the window used. It is not reliable. |

**When you believe a boundary has arrived, you get one line and then you stop:**

> Pull request #42 is merged and the tree is clean. Clean break if you want it — say the word and I'll write the handoff.

Then **do nothing**. Do not draft it "so it's ready". Do not write it to a scratch file. Do not start the verification commands. The user says yes, or they don't.

## Gate 2 — Is anything in flight that dies with this session?

A handoff is worthless if ending the session destroys the work it describes. **Classify every running thing before you write:**

**Re-attachable — a fresh session can pick it up from an identifier.** The handoff is allowed, and the `**Start:**` line MUST be the re-attach command.

- a hosted CI run with an id (on GitHub: `gh run view <id>`)
- checks on a pull request (on GitHub: `gh pr checks <number>`)
- a job on a remote host or in a job queue that keeps running when this terminal closes, with the id or command that finds it again

**Not re-attachable — it dies when the session ends.** The handoff is **refused**.

- a subagent still running inside this session
- a monitor or watcher this session started
- a background shell job this session owns
- a local build, server, or test run you started
- an unfinished multi-step edit, an uncommitted refactor mid-flight

**On a refusal, say exactly what is running and offer the two real options — write no file:**

> Not a clean break. The integration suite is on test 212 of 340 in a local process; it dies when this session ends and there is no run id to re-attach to. Want me to wait for it and then write the handoff, or stop it and hand off without the result?

Never write the file and flag the problem in it. The user's decision comes first.

## Gate 3 — Is this the session's last act?

If you intend to do anything after the handoff, you are not at a handoff.

`/handoff and then fix the retry bug` does **not** mean *write the file, then fix the bug*. It means: the bug is the next session's first task, written into `## Still to do`. It does not get fixed now.

**Check before writing:** is there a todo still open that you were planning to finish? Then either finish it first and then write, or write it into `## Still to do`. There is no third option where you write the file and keep going.

---

# PART 2 — THE TERMINAL RULE

**The handoff is the last thing the session does. One invocation, one file, one write, and the path is the last thing you say.**

Once the file is written, your message ends with the absolute path of the file on its own line, for example:

```
<handoff root>/<project>/<stream>.md
```

plus its `wc -lm` counts. Then you stop. No further tool calls. No "while you read that, I'll…". No starting the next item.

**Why this is absolute:** measured across a few hundred real sessions, about a quarter kept working after writing the handoff, some for hundreds of further transcript lines. In every one of those the path scrolled out of view and the user could no longer find the file that had been written for them. A handoff the user cannot see is not a handoff.

**Writing it twice is the same failure.** In the same measurement, about one session in five wrote its handoff more than once. If you already wrote a handoff this session, you do **not** write another on your own — not to "update it", not because more happened. More happening after the handoff means Gate 3 was broken. If the user explicitly asks again after further work, that is a new invocation: rewrite fresh (Part 4) and stop again.

**Never split across two files.** One stream, one file. If it feels like two streams, it is two handoffs in two *sessions*, not two files in one.

---

# PART 3 — WHERE IT GOES, AND THE LIFECYCLE

```
<root>/<project>/<stream>.md   <- LIVE. Nothing else lives here.
<root>/<project>/done/         <- archived. Finished streams.
```

`<root>` is `$HANDOFF_DIR` when that variable is set. Otherwise it is the `handoffs` folder in the Claude Code configuration directory: `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/handoffs`. It sits outside every repository, so a handoff cannot be committed by accident.

**Top level means live.** Listing `<project>/` must return only streams a fresh session could legitimately pick up.

## `<project>` — one rule

`<project>` is the **directory name of the repository's main working tree**: the basename of the first entry printed by `git worktree list --porcelain`. Every worktree of one repository therefore shares one folder. Outside a git repository, it is the basename of the current directory.

Resolve it with this, which runs unchanged on macOS and Linux:

```bash
main=$(git worktree list --porcelain 2>/dev/null | sed -n '1s/^worktree //p')
project=$(basename "${main:-$PWD}")
root="${HANDOFF_DIR:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/handoffs}"
dir="$root/$project"
mkdir -p "$dir"
echo "$dir"
```

Do not derive the name any other way — not from the remote URL, not from the branch, not from the worktree you happen to be in. A handoff filed under a different name is a handoff nobody finds.

## `<stream>` — the thread of work, not the project

Several streams run in one repository at once: a bug fix on one branch, a migration on another, a spike in a third worktree. One file per project would overwrite all but the last. Name the file after *this thread of work*: the branch name, the issue number, or the feature.

Make it a plain file name: lower case, with `/` and spaces replaced by `-`. Branch `fix/rounding-on-refund` becomes `fix-rounding-on-refund.md`.

## The header is machine-read — keep it exact

The companion `pickup` skill and other tools parse these lines to find the right handoff, so the format is fixed:

```markdown
**Project:** `<project>`
**Repo:** `<absolute path of THIS checkout>`   **Branch:** `<branch>`   **Written:** <YYYY-MM-DD>
**Start:** <first command>
```

- **`**Project:**`** is the resolved project name from the rule above, in backticks. It equals the folder the file sits in.
- **`**Repo:**`** is the absolute path of the checkout you actually worked in — the worktree, not the main working tree — in backticks. One repository with several checkouts is normal; never assume the reader is in the directory you were in.
- **`**Branch:**`** is the branch name, in backticks, first thing after the marker: the output of `git branch --show-current`. Extra words after the backticked name are fine. Not `merged to main`, not prose. On a detached HEAD write `` `detached@<short-sha>` ``. Outside a git repository write `` `none` ``.
- **`**Written:**`** is today's date as `YYYY-MM-DD` (`date +%Y-%m-%d`).

## Archiving a finished stream

When the work a handoff describes is **done** — merged, shipped, closed, abandoned — it does not get another handoff. It gets archived:

```bash
mkdir -p "$dir/done"
target="$dir/done/<stream>.md"
# A reused stream name must not overwrite an earlier archive.
if [ -e "$target" ]; then target="$dir/done/<stream>-$(date +%Y%m%d-%H%M%S).md"; fi
mv "$dir/<stream>.md" "$target"
```

Say so in one line: `Stream finished — archived to done/, nothing to pick up.`

Do **not** write a final handoff whose content is "everything is done". That is a status report, and it reads as live work that no longer exists.

Do **not** invent your own in-file marker (`## CONSUMED`, `SUPERSEDED`, a strikethrough banner). `done/` is the marker.

---

# PART 4 — REWRITE FRESH. NEVER EDIT.

**Use `Write`. Never `Edit` a handoff file.** Not once, not for a one-line fix.

A continuing stream can run ten or twenty handoffs deep. Editing carries the old file forward by default and drops only what you happened to notice — which is exactly how a `## Still to do` item you finished three sessions ago survives to waste the next session's time.

**The procedure:**

1. **Read** the existing file for this stream, if there is one.
   - **Check it is yours before you replace it.** Two repositories whose folders share a name share a `<project>` folder, and two branch names can shorten to the same file name. If the existing file's `**Repo:**` is a checkout of a different repository, or its `**Branch:**` is a different branch that is still live, it is someone else's stream: do not overwrite it. Pick a distinct file name for yours (add the repository owner, or the part of the branch name that differs) and say in one line that you did.
2. **Re-derive every line.** For each thing in the old file, ask: *is this still true, today, verified this session?*
   - Done → **drop it.** No strikethrough, no "(completed)". Gone.
   - Still true → carry it forward, rewritten.
   - Unsure → verify it now, or cut it. Never carry an unverified line.
3. **`Write`** the new file over the same path.

**Dead ends are the exception that must survive.** A dead end stays load-bearing long after the work around it changed — a revert leaves no trace in git by construction, so if you drop it, it is gone permanently and the next session re-runs your failure. Carry every dead end still in force, every time, however deep the stream.

---

# PART 5 — VERIFY BEFORE YOU WRITE

You are writing at the moment your context is most degraded — exactly when confident fiction appears: tests that "pass" but were never re-run, file descriptions twenty edits stale. Run these in the checkout and write from the output, not from memory:

```bash
git status --short
git branch --show-current
git log --oneline '@{u}..HEAD' 2>/dev/null   # unpushed commits; silent with no upstream
git stash list
if command -v gh >/dev/null 2>&1; then gh pr status 2>/dev/null | head -20; fi
```

Each line is optional. Outside a git repository, skip the `git` lines and describe the state of the files directly. Without `gh`, or when the project is not hosted on GitHub, skip the last line and state pull-request or review status only if you checked it some other way this session.

If you assert a test passes, you ran it this session. If you cannot verify a claim cheaply, cut it — do not soften it.

---

# PART 6 — THE RECIPE

Order is deliberate: blocking first, then what will waste the reader's time, then the work. Attention depletes as the file goes, so nothing load-bearing sits at the bottom.

**Size: whatever the gates admit.** Typical is 1,500–2,500 tokens (~6,000–10,000 characters). That is an observed range, **not a floor and not a ceiling**. Never pad to reach it; never cut something load-bearing to stay under it.

```markdown
# Continue — <project>: <stream>

**Project:** `<project>`
**Repo:** `<absolute path of THIS checkout>`   **Branch:** `<branch>`   **Written:** <YYYY-MM-DD>
**Start:** <the single first command, assuming a shell in the repo above.
           If something re-attachable is running, this IS the re-attach command.>

## Blocking
<only what the user must decide before work can proceed. If nothing, write "nothing".>

## Dead ends
<approaches tried that did NOT work, and why. THE HIGHEST-VALUE SECTION — a revert leaves
no trace in git by construction, so this is the one thing a fresh session can never
reconstruct; without it, it re-runs your failures. Tie each to the open item it affects.
Carry forward every still-relevant entry from the previous handoff.>

## What will mislead you
<anything that would send the reader down a wrong path: a doc or issue body that is now
false (name it), a red signal that is a known false alarm, a convention that differs from
the tool default. Not "things we tried" — that is Dead ends.>

## In flight
<state that is real but not final: uncommitted files, unpushed commits, a pushed branch
with no pull request, a migration written but not applied, a CI run still going (with its
id and the command to re-attach). Say what is ambiguous about each.>

## Still to do
<remaining work, concrete enough to act on: file, symbol, or command per item.
Nothing already finished appears here.>

## Decisions and why
<rationale for choices still load-bearing on the next session's work — including the
alternatives rejected. Not a decision log; only what changes what happens next.>

---
Re-verify anything above that you are about to act on, and report what has drifted.
```

## What earns a line

Two gates. An entry must pass both. **There is no size target that overrides them** — in either direction.

**1. Recoverability — can the next session get this in one command?**

| | Where from | Write |
|---|---|---|
| What shipped, what closed | `git log`, the issue tracker | nothing |
| Build/test/release mechanics | `CLAUDE.md`, `AGENTS.md`, the README | nothing |
| Architecture, conventions | project docs | nothing |
| Current file contents | the file | nothing |
| **Why an approach was abandoned** | **nowhere** — a revert erases it | keep |
| **Why a live decision was made** | commits sometimes; reconstructing it later is unreliable and tends to fabricate | keep |
| A doc that is currently stale | nowhere | keep |
| A false alarm already diagnosed | nowhere | keep |

Recoverable means *redundant*, not *cheap*: `git log --oneline -30` on a large repository is several hundred tokens. Deferring is often dearer than carrying. Use this gate to cut duplication, not to shrink the file.

**In flight** is the deliberate exception. A status command would find the branch, but the reader has to know to look and know it matters — state it, in one line, without restating what the command would print.

**2. The stranger test — would someone holding only this line avoid the mistake we made?**

If not, it needs a file, a line number, and a reason, or it gets cut.

## Worked example

A real handoff runs longer than this in both directions. The shape is what to copy, not the length. The project, paths, and numbers below are invented.

```markdown
# Continue — parcel-tracker: webhook retry backoff

**Project:** `parcel-tracker`
**Repo:** `/srv/checkouts/parcel-tracker-retry`   **Branch:** `fix/webhook-retry-backoff`   **Written:** 2025-03-14
**Start:** `git fetch && git status --short && gh pr checks 318`

## Blocking
- Whether the retry ceiling is 6 attempts or 8. Carrier B's contract says "at least 24 hours of
  retries"; 6 attempts reach 21 hours. Needs a human call before `RetryPolicy` is final.

## Dead ends
- **Jitter computed in the scheduler** — moving jitter out of `RetryPolicy.next_delay` into
  `scheduler/enqueue.py` made delays untestable without a clock fake in two modules and broke
  the idempotency key, which hashes the scheduled time. Two rounds, then reverted. Jitter stays
  in the policy. **Load-bearing for issue 327 — do not restart it there.**
- **Deduplicating deliveries on the carrier's event id** — Carrier A reuses event ids across
  shipments after about 30 days, so the dedupe dropped real events in the replay fixture.
  Reverted; dedupe is on `(shipment_id, event_id)` only.
- **Running the replay suite in parallel** — the workers share one SQLite fixture file and
  corrupt each other's state, giving nondeterministic failures. **Affects the remaining
  replay work:** run it serially, or give each worker its own copy.

## What will mislead you
- `docs/webhooks.md` says failed deliveries retry "every 5 minutes". False since the backoff
  change on this branch; the doc is updated last, on purpose, after the ceiling is decided.
- Issue 318's description lists a dead-letter queue as missing. It exists
  (`queue/dead_letter.py`); read the code before building from the issue.
- `test_retry_timing_under_load` fails about one run in ten on a laptop and never in CI. It is
  a known timing flake, not a regression — do not chase it.
- `make test` skips the replay suite unless `REPLAY=1` is set. A green `make test` says nothing
  about replay.

## In flight
- `migrations/0047_delivery_attempts.sql` is written and committed but NOT applied to the
  staging database. Nothing reads the new column yet.
- Branch is pushed; pull request 318 is open as a draft. Checks were green at `7c1e4b9`. The two
  commits after it are local only — `git log --oneline '@{u}..HEAD'` shows them.
- `fixtures/replay/carrier_b.jsonl` is modified and uncommitted: three events added by hand to
  reproduce the 21-hour gap. Keep them; they are the regression case.

## Still to do
- `RetryPolicy.next_delay` (`delivery/retry.py:61`) caps at attempt 6. Make the ceiling a
  setting once the Blocking question is answered; failing test first.
- `delivery/worker.py:140` still logs the old fixed delay. Log the computed one.
- Apply migration 0047 on staging, then run `REPLAY=1 make test` serially.
- Update `docs/webhooks.md` last.

## Decisions and why
- Backoff is exponential with full jitter, not decorrelated jitter: the carriers rate-limit per
  sender, and full jitter gave the flattest request curve in the replay. Decorrelated jitter
  was tried on paper only and rejected because its upper bound is harder to explain to the
  carrier in the contract.
- The dead-letter queue keeps payloads for 14 days, not 30: payloads carry recipient addresses
  and the retention policy caps personal data in queues at 14 days.

---
Re-verify anything above that you are about to act on, and report what has drifted.
```

---

# PART 7 — CLOSING OUT

Your final message contains the **absolute path on its own line**, plus the counts:

```bash
wc -lm "$dir/<stream>.md"   # -m counts characters; -c would count bytes
```

Tell the user how to resume: start a new session in the same repository and paste the path, for example `Read <path> and continue from it`. If the `pickup` skill is installed, `/pickup <stream>` in the new session finds the file without the path.

Then stop. See Part 2.

---

# Common mistakes

**Writing one nobody asked for.** The single most common failure — about a third of the handoffs measured. Offer in one line; wait.

**Writing one over live, un-re-attachable work.** A session wrote a handoff with the words *"Last test still running. Let me write the handoff now while the result is fresh."* The run died with the session. Gate 2 exists for this.

**Continuing to work after writing it.** The path scrolls away and the file is effectively lost.

**Editing instead of rewriting.** Finished work survives in `## Still to do` and the next session redoes it.

**Cutting dead ends to save space.** The least recoverable thing you know. Cut a status recap instead.

**Cutting rationale because "it's in the commit."** Commits record what landed, not what was rejected. Reconstructing rationale afterwards is unreliable — a missing *why* invites a confident wrong *why*.

**Writing a session recap.** What happened is in `git log`. The reader needs what is *true*.

**Splitting overflow into a second file.** If it belongs in the handoff, it goes in the handoff.

**Filing the same fact twice** across Dead ends and What-will-mislead-you. Tried-and-failed goes in Dead ends; everything else that costs time goes in the other.

**Leaving a finished stream at the top level.** Archive it to `done/` so nobody picks up dead work.

**Filing it under the wrong project folder.** Use the rule in Part 3, not the name of the worktree you are in.

# Red flags

- You are writing a handoff and nobody asked for one
- A percentage or a context warning is your reason for writing
- Something is running that has no run id, and you are writing anyway
- You have already written a handoff this session
- You are about to use `Edit` on a handoff file
- You are about to do anything at all after printing the path
- `## Dead ends` is empty after a session that hit real obstacles
- You are writing "## What we accomplished"
- You are about to reference a second file instead of including the content
- You named the file after the repository instead of the work stream
- You asserted a test result or branch state you did not check this session
