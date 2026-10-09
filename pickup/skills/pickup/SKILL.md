---
name: pickup
description: Use ONLY when the user types "/pickup" (with or without a stream name) or explicitly asks to resume from a handoff — "pick up the handoff", "resume from the handoff", "carry on from the handoff file". Finds the handoff for this checkout, shows which one it chose and why before reading it, then verifies it and starts work. Do NOT use on a bare "continue", "resume" or "keep going" with no mention of a handoff.
allowed-tools:
  - Bash(sh ${CLAUDE_SKILL_DIR}/list-handoffs.sh *)
  - Bash(sh "${CLAUDE_SKILL_DIR}/list-handoffs.sh" *)
---

# Pickup

The other half of the `handoff` skill. A previous session wrote one Markdown file for this stream of work; find it, **show the user which file you chose and why**, and only then load it.

**Experimental.** The selection rules may change.

**Requires the handoff skill.** It writes the files this skill reads, and it defines where they are stored and what their first lines mean. This skill does not redefine either. The plugin declares that dependency, so installing it as a plugin brings the handoff skill with it.

**Why the choice is shown:** a pickup that chooses silently is right most of the time and wrong without warning. One wrong pick costs more than every right one saves, because the user stops trusting it and goes back to pasting paths. So the choice is never silent, not even when it is obvious.

## When to use it

Only these start a pickup:

- `/pickup`, or `/pickup <name>`
- an explicit request to resume from a handoff: "pick up the handoff", "resume from the handoff", "carry on from the handoff file"

A bare "continue", "resume", "keep going" or "carry on" is **not** a pickup. It means continue what this session was already doing.

## Step 1 — Run the script. Read no handoff yet.

From the directory the user is working in:

```sh
sh "${CLAUDE_SKILL_DIR}/list-handoffs.sh"            # /pickup
sh "${CLAUDE_SKILL_DIR}/list-handoffs.sh" "<name>"   # /pickup <name>, or "pick up the retry one"
```

`list-handoffs.sh` sits in the same folder as this file. If the path above does not resolve, use that folder's path, which is shown as this skill's base directory when the skill loads.

If the user gave a name or a hint ("the retry one", `/pickup issue-327`), pass it as the argument. Do not choose by it yourself.

The script only reads. It finds the store and the project by the handoff skill's rule and prints a listing. **Do not** list the store yourself, guess from file names, read git history to find a handoff, or look in `done/`. If the script fails, show its error and stop.

### Reading the listing

The top lines describe the run. The ones that decide what you do:

| Line | Meaning |
|---|---|
| `confidence: single` | Exactly one live handoff for this project. |
| `confidence: clear` | Several, and one has stronger evidence than every other. |
| `confidence: ambiguous` | Several, and the best ones cannot be told apart. |
| `confidence: none` | No live handoff, or none matching the name given. |
| `proposed: 1 <stream>` | The script's choice: block `[1]`. `proposed: none` means it made no choice. |
| `action: load` | `single` or `clear`, and the proposed handoff has no flag. |
| `action: ask` | Anything else with candidates. The user chooses. |
| `action: none` | Nothing to pick up. |

Then one block per candidate, best first. Each has its `path:`, its `written:` date, the `recorded-repo:` and `recorded-branch:` it was written in, and:

- `reason:` lines — evidence that this is the one, with points. `name-exact`, `name-partial`, `repo-path`, `branch`.
- `weak:` lines — a match that proves nothing: both on a default branch such as `main`, or both on a detached HEAD. It adds no points. A `commit` line says how far this checkout has moved from the commit the handoff recorded; it is context for the user, not a flag.
- `flag:` lines — something the user should know before trusting it: `stale`, `repo-missing`, `branch-missing`, `different-checkout`, `different-branch`, `different-commit`, `pr-merged`, `pr-closed`, `legacy-project`, `header-incomplete`.

`pr: unknown` and `pr: not-checked` mean the pull request could not be checked. They do not mean there is none.

## Step 2 — Show the choice. Always, and before reading the file.

Every pickup shows the user, **before any handoff file is opened**:

1. the chosen file: stream name and full path;
2. the reasons, in plain words;
3. its flags, or that it has none;
4. the alternatives: every other candidate, each with its stream name, date and the one fact that sets it apart. With none, say there were no others.

Then act on the `action:` line.

### `action: load`

State the choice in one or two lines, then load it. No question.

> Picking up **fix-label-printer** (`/srv/handoffs/parcel-tracker/fix-label-printer.md`): written 2 days ago in this checkout, on the branch checked out here. No flags. One other live handoff: **search-index**, written on another branch.

### `action: ask`

Show the numbered candidates and ask the user to choose **by number or by name**. Read nothing until they answer.

When the script proposed one and it is flagged, lead with it and its flags:

> The best match is **fix-label-printer**, but it is flagged: written 40 days ago (stale), and its pull request #41 is merged.
>
> 1. **fix-label-printer** — written 40 days ago, branch checked out here, PR merged
> 2. **search-index** — written 3 days ago, on `feat/search-index`, in another checkout
>
> Which one, by number or name? Or none, if this is new work.

When nothing is proposed (`ambiguous`, or a name that matched nothing), say why no choice was made and list them all the same way:

> Three live handoffs were written here on `main`, and a default branch does not tell them apart:
>
> 1. **billing-export** — written today
> 2. **search-index** — written today
> 3. **login-rate-limit** — written 3 days ago
>
> Which one, by number or name?

**Never adopt another stream on your own.** Not the newest, not the only one left, not the one whose name looks right. A handoff written on another branch or in another checkout belongs to other work until the user says otherwise.

If the listing has `skipped:` lines, mention them in one line: they are files in this project's folder whose own header names a different project.

### `action: none`

Say there is nothing to pick up, mention the `archived:` count if it is not zero, and ask what the work is. Do not create a folder, and do not look in `done/` unless asked.

If the `store:` line says `(does not exist)`, no handoff has ever been written on this machine with these settings. Say so: handoffs are written by the handoff skill (`/handoff`), which this skill needs and does not replace.

## Step 3 — Load, verify, start

Once a handoff is chosen, by the script with no flags or by the user:

1. **Read the file once, whole.**
2. **Verify its recorded state against this checkout.** The handoff describes the past. Check what you are about to rely on:
   - you are in the checkout its `**Repo:**` names, on the branch its `**Branch:**` names;
   - what `## In flight` claims: uncommitted files, unpushed commits, an open pull request, a run still going;
   - anything in `## Still to do` that may since have been done.
3. **Report only what drifted**, in a few lines. Do not repeat the handoff back to the user: they wrote it, and reprinting it spends the fresh context this session exists for. If nothing drifted, say so in one line.
4. **Run its `**Start:**` step.** Show the command first. If it does anything beyond reading state or re-attaching to a run — deleting, pushing, deploying — ask before running it.
5. **Begin with `## Blocking`** if it is not empty: ask the user those questions and wait. Otherwise begin with `## Still to do`.

`## Dead ends` is not a list of ideas. Those approaches were tried and failed. Do not re-run them to check. If you believe one is wrong, say so and why before spending anything on it.

## Step 4 — Offer to archive a finished stream

When the work the handoff describes is finished — merged, shipped, closed or abandoned — offer to archive it, and do it when the user agrees:

```sh
dir=$(dirname "<path of the handoff>")
mkdir -p "$dir/done"
target="$dir/done/<stream>.md"
# A reused stream name must not overwrite an earlier archive.
if [ -e "$target" ]; then target="$dir/done/<stream>-$(date +%Y%m%d-%H%M%S).md"; fi
mv "<path of the handoff>" "$target"
```

A `pr-merged` flag is a reason to **ask**, not proof. A merged pull request often leaves follow-up work in `## Still to do`, and the stream may belong to a session that is still running.

If the work is not finished, leave the file alone. Writing the next handoff is the handoff skill's job, and only when the user asks for it.

## Red flags

- You are about to read a handoff and have not yet told the user which one and why
- You opened a handoff to help decide between candidates
- `action: ask`, and you chose for the user
- You picked the newest file, or the one with the most promising name, without the script proposing it
- You adopted a handoff flagged `different-checkout` or `different-branch` without asking
- You listed the store or searched `done/` yourself instead of running the script
- You treated `pr: unknown` or `pr: not-checked` as "no pull request"
- You are reprinting the handoff's contents back to the user
- You are retrying something listed under `## Dead ends`
- You archived a handoff without the user agreeing
- You started a pickup because the user said "continue"
