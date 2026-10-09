# handoff

A Claude Code skill that writes one Markdown file at the end of a coding session so a fresh session can continue the work.

## The problem

Long agent sessions get worse as the context window fills, so at some point you start a new one. The new session can read the code and the git history, but it cannot recover what the old session learned the hard way:

- the approaches that were tried and reverted (a revert leaves no trace in git);
- the signals that look like problems and are not, and the docs that are now wrong;
- what is half-finished: uncommitted files, unpushed commits, a CI run still going;
- why the live decisions were made, including what was rejected.

Without that, the new session repeats the old one's failures. A handoff is the file that carries exactly those things across, and nothing the next session could look up for itself.

## What the skill does

You type `/handoff`. The agent then:

1. **Checks three gates**, and writes nothing unless all pass:
   - you asked for it (a full context window, or a finished task, is never a reason on its own);
   - nothing is running that would die with the session and cannot be re-attached;
   - it is the session's last act.
2. **Verifies the state** with `git` (and `gh`, when installed) instead of writing from memory.
3. **Writes one file, fresh.** If a handoff for this stream of work already exists, it is re-derived line by line and rewritten, never edited, so finished work drops out and dead ends survive.
4. **Prints the file's path and stops.**

When a stream of work is finished, the agent moves its handoff into a `done/` folder instead of writing another.

Requirements: Claude Code and a POSIX shell, on macOS or Linux. `git` and `gh` are optional; the skill works outside a git repository and on projects that are not on GitHub.

## Install

Pick one.

### As a Claude Code plugin

```sh
claude plugin marketplace add dmealing/dougs-ai-tools
claude plugin install handoff@dougs-ai-tools
```

Inside a session, the same two steps are `/plugin marketplace add dmealing/dougs-ai-tools` and `/plugin install handoff@dougs-ai-tools`.

Plugin skills carry the plugin's name as a prefix, so the command is `/handoff:handoff`. Asking in words ("hand this off") works too.

### With the install script

```sh
git clone https://github.com/dmealing/dougs-ai-tools.git
sh dougs-ai-tools/handoff/install.sh
```

This copies the skill to `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills/handoff/SKILL.md`, and the command is `/handoff`.

| Command | Effect |
|---|---|
| `sh install.sh` | Install. Does nothing if the same version is already there. Refuses to overwrite a file that differs. |
| `sh install.sh --force` | Install, replacing a file that differs. |
| `sh install.sh --uninstall` | Remove the skill. Refuses if the installed file differs from the shipped one. |
| `sh install.sh --uninstall --force` | Remove the skill even if it was modified. |

Install it one way, not both, or the skill is listed twice.

## Where handoffs are stored

```
~/.claude/handoffs/<project>/<stream>.md    live handoffs
~/.claude/handoffs/<project>/done/          finished streams
```

- **`<project>`** is the directory name of the repository's main working tree (the first entry of `git worktree list --porcelain`), so every worktree of one repository shares one folder. Outside a git repository it is the name of the current directory.
- **`<stream>`** names the thread of work, usually the branch with `/` replaced by `-`. Several streams can be live in one project at once.

Handoffs live outside the repository so they cannot be committed by accident. If `CLAUDE_CONFIG_DIR` is set, the `handoffs` folder is created there instead of in `~/.claude`.

Finished handoffs accumulate in `done/` and are never deleted automatically. Delete that folder's contents yourself when you no longer want them.

### Storing them somewhere else

Set `HANDOFF_DIR` to replace `~/.claude/handoffs` with another directory, for example in your shell profile:

```sh
export HANDOFF_DIR=/tmp
```

Handoffs then go to `/tmp/<project>/<stream>.md`. A temporary directory such as `/tmp` is wiped on restart, so use one only for handoffs you pick up the same day.

## What a handoff looks like

A shortened, invented example:

```markdown
# Continue — parcel-tracker: webhook retry backoff

**Project:** `parcel-tracker`
**Repo:** `/srv/checkouts/parcel-tracker-retry`   **Branch:** `fix/webhook-retry-backoff`   **Written:** 2025-03-14
**Start:** `git fetch && git status --short && gh pr checks 318`

## Blocking
- Whether the retry ceiling is 6 attempts or 8. Needs a human call before `RetryPolicy` is final.

## Dead ends
- **Jitter computed in the scheduler** — broke the idempotency key, which hashes the scheduled
  time. Reverted; jitter stays in `RetryPolicy`. Do not restart it for issue 327.

## What will mislead you
- `docs/webhooks.md` says failed deliveries retry "every 5 minutes". False since this branch.
- `test_retry_timing_under_load` fails about one run in ten locally. Known flake, not a regression.

## In flight
- `migrations/0047_delivery_attempts.sql` is committed but NOT applied to staging.
- Two commits are local only; checks were green at `7c1e4b9`, before them.

## Still to do
- `RetryPolicy.next_delay` (`delivery/retry.py:61`) caps at attempt 6. Make it a setting.

## Decisions and why
- Full jitter, not decorrelated jitter: it gave the flattest request curve in the replay.

---
Re-verify anything above that you are about to act on, and report what has drifted.
```

The first four header fields (`**Project:**`, `**Repo:**`, `**Branch:**`, `**Written:**`) have a fixed format so that tools can read them. The full template and a longer example are in [the skill itself](skills/handoff/SKILL.md).

## Resuming from a handoff

The skill ends by printing the file's absolute path. Start a new Claude Code session in the same repository and paste it:

```
Read ~/.claude/handoffs/parcel-tracker/fix-webhook-retry-backoff.md and continue from it.
```

The printed path is absolute; `~` is used here only to keep the example short. To see what is live for a project, list its folder: `ls ~/.claude/handoffs/<project>/`.

## Tests

```sh
sh handoff/tests/run.sh
```

Run it from the repository root. It tests `install.sh` against a throwaway directory, checks the shipped files for absolute home paths and for shell that stock macOS lacks, and runs `shellcheck` when it is installed.

## Related

More tools for working across sessions are planned in this repository. This skill does not need them.

## Licence

Apache-2.0. See [LICENSE](../LICENSE).
