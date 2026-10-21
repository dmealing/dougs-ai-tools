# Handoff reference

Read on demand: the full test for what goes in a handoff, a worked example, and mistakes that the gates in SKILL.md do not already cover.

# What earns a line

An entry must pass both tests, whatever the resulting size.

**1. Can the next session recover it with one command?** What shipped (`git log`), build and test mechanics (`CLAUDE.md`, the README), architecture and conventions (project docs) and current file contents are recoverable: leave them out. Why an approach was abandoned, why a live decision was made, a doc that is now stale and a false alarm already diagnosed are recoverable nowhere: keep them. Recoverable means redundant, not cheap. **In flight** is the exception: state it in one line even though a status command would find it.

**2. Would someone holding only this line avoid the mistake we made?** If not, add the file, line number and reason, or cut it.

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

**Cutting rationale because "it's in the commit."** Commits record what landed, not what was rejected, and a missing *why* invites a confident wrong one.

**Writing a session recap.** What happened is in `git log`. The reader needs what is true now.

**Splitting overflow into a second file.** If it belongs in the handoff, it goes in the handoff.

**Filing one fact twice.** Tried-and-failed goes in Dead ends; anything else that costs time goes in What will mislead you.
