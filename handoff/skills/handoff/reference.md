# Handoff reference

Read on demand by the handoff skill: the worked example when the shape of a section is unclear, the mistakes list when something feels off. Nothing here changes the gates in SKILL.md.

# What earns a line

An entry must pass both tests. **No size target overrides them**, in either direction.

**1. Recoverability — can the next session get this in one command?** What shipped (`git log`), build and test mechanics (`CLAUDE.md`, the README), architecture and conventions (project docs) and current file contents are recoverable: write nothing. **Why an approach was abandoned**, **why a live decision was made**, **a doc that is currently stale** and **a false alarm already diagnosed** are recoverable nowhere: keep them. Recoverable means *redundant*, not *cheap*, so use this test to cut duplication, not to shrink the file. **In flight** is the deliberate exception: state it in one line even though a status command would find it.

**2. The stranger test — would someone holding only this line avoid the mistake we made?** If not, it needs a file, a line number and a reason, or it gets cut.

# Worked example

A real handoff runs longer than this in both directions. The shape is what to copy, not the length. The project, paths, and numbers below are invented.

```markdown
# Continue — parcel-tracker: webhook retry backoff

**Project:** `parcel-tracker`
**Repo:** `/srv/checkouts/parcel-tracker-retry`   **Branch:** `fix/webhook-retry-backoff`   **Written:** 2025-03-14
**Commit:** `a41f09c`
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

# Common mistakes

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
