---
name: pickup
description: Use ONLY when the user types "/pickup" (with or without a stream name) or explicitly asks to resume from a handoff — "pick up the handoff", "resume from the handoff", "carry on from the handoff file". Finds the handoff for this checkout, shows which one it chose and why before reading it, then verifies it and starts work. Do NOT use on a bare "continue", "resume" or "keep going" with no mention of a handoff.
allowed-tools:
  - Bash(sh ${CLAUDE_SKILL_DIR}/list-handoffs.sh *)
  - Bash(sh "${CLAUDE_SKILL_DIR}/list-handoffs.sh" *)
---

# Pickup

Resume from a file the `handoff` skill wrote. Choose it with the script, tell the user which file and why, and only then read it. The choice is never silent, even when it is obvious: one wrong silent pick costs more than every right one saves, because the user stops trusting the tool.

A bare "continue", "resume" or "keep going" is not a pickup. It means carry on with what this session was doing.

## 1. Run the script

From the user's working directory:

```sh
sh "${CLAUDE_SKILL_DIR}/list-handoffs.sh"            # /pickup
sh "${CLAUDE_SKILL_DIR}/list-handoffs.sh" "<name>"   # /pickup <name>, or a hint such as "the retry one"
```

If `${CLAUDE_SKILL_DIR}` does not resolve, use the base directory shown when this skill loaded; the script sits beside this file.

Pass any name or hint the user gave as the argument and let the script match it. Find handoffs only through the script: do not list the store, look in `done/` or search git history. If it fails, show its error and stop. Its output explains each reason, flag and weak match in place.

## 2. Show the choice before reading any handoff

Tell the user the chosen stream and its full path, the reasons in plain words, its flags or that it has none, and every other candidate with its date and the one fact that sets it apart. Then follow the `action:` line:

- `load`: say it in a line or two, then read the file. No question.
- `ask`: number the candidates, lead with any flags on the proposed one (or, when none is proposed, say why the script made no choice), and ask which one, by number or name, or none if this is new work. Read nothing until the user answers.
- `none`: say there is nothing to pick up, give the `archived:` count if it is not zero, and ask what the work is. If `store:` says `(does not exist)`, say that handoffs are written by the handoff skill (`/handoff`). Create nothing.

Never adopt a stream on your own, not even the newest or the only one left: a handoff written on another branch or in another checkout belongs to other work until the user says otherwise. Mention any `skipped:` lines in one line.

## 3. Load, verify, start

1. Read the file once, whole.
2. Check what you will rely on against this checkout: its `**Repo:**` and `**Branch:**`, what `## In flight` claims, and whether anything in `## Still to do` is already done.
3. Report only what drifted, in a few lines, or that nothing did. Do not reprint the handoff: the user wrote it, and the fresh context is what this session is for.
4. Show the `**Start:**` command, then run it. Ask first if it does more than read state or re-attach to a run.
5. If `## Blocking` has questions, ask them and wait. Otherwise begin with `## Still to do`.

`## Dead ends` were tried and failed. Do not re-run one to check; if you think one is wrong, say why before spending anything on it.

## 4. Offer to archive a finished stream

When the work is finished (merged, shipped, closed or abandoned), offer to archive the handoff, and do it only when the user agrees. A `pr-merged` flag is a reason to ask, not proof: follow-up work may remain, and the stream may belong to a session that is still running.

```sh
dir=$(dirname "<path of the handoff>")
mkdir -p "$dir/done"
target="$dir/done/<stream>.md"
# A reused stream name must not overwrite an earlier archive.
if [ -e "$target" ]; then target="$dir/done/<stream>-$(date +%Y%m%d-%H%M%S).md"; fi
mv "<path of the handoff>" "$target"
```

If the work is not finished, leave the file alone. The next handoff is written by the handoff skill, when the user asks for one.
