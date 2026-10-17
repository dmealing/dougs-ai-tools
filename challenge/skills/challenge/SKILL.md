---
name: challenge
description: Use ONLY when the user types "/challenge" or explicitly asks for a cross-model second opinion on a conclusion — "challenge this", "stress-test this recommendation with two independent runs". Experimental. Every run starts two headless Claude sessions plus a differential step, which uses plan quota or metered money, so never start it on your own initiative or because the user merely disagrees.
disable-model-invocation: true
allowed-tools:
  - Bash(sh ${CLAUDE_SKILL_DIR}/challenge-log.sh *)
  - Bash(sh "${CLAUDE_SKILL_DIR}/challenge-log.sh" *)
  - Bash(sh ${CLAUDE_SKILL_DIR}/challenge-run.sh *)
  - Bash(sh "${CLAUDE_SKILL_DIR}/challenge-run.sh" *)
---

# Challenge

> **Experimental.** The wording rules, the scripts and the log format may change.

## What it costs — say this before you dispatch

Every run starts **two headless `claude -p` sessions** (the arms), then a **differential step** of two calls on a third, cheaper model. On a subscription login that uses plan quota; with an API key it is metered money. The per-arm cap (`--max-budget-usd`) is the CLI's own estimate and can be passed.

The default pair is **Opus 5.5 and Opus 5**. Fable 5.1 is opt-in with `--fable`: it costs 2.5 times Opus 5.5 per token, and under `-p` Claude Code does **not** ask before a Fable request bills to usage credits. Do not add `--fable` unless the user asked for it, and tell them that when you do.

Tell the user this in one line when you begin, so the spend is never a surprise. `reference.md` has dated figures from the author's own use.

## Overview

A challenge sends **one neutral brief to two independent adjudicators**, then hands the user a **differential**: where the two converged, where they split, which splits a check settles, which are a real decision, and what only one of them raised. It never picks a winner.

Core principle: **a second opinion is only evidence if it could have disagreed.** An adjudicator told it is the authority, reviewed by someone who already trusts it, produces agreement, not information.

Use it when you suspect a recommendation is wrong and cannot say why, or when the alternative is asking one model you trust more. Do not use it when the decision has no consequence.

## Step 1 — State the stakes, in one line

Answer: **what changes if this call is wrong?**

- `high` — wrong costs real work, ships a defect, or is hard to reverse
- `low` — wrong is caught cheaply, or costs one revert
- `none` — both branches converge

**If `none`, stop. Do not dispatch.** Say so and move on. A `low` challenge may be run, but it will rarely split, and the log only counts `high` rows.

## Step 2 — Write ONE neutral brief

Create the record, which writes a template to `<record-dir>/brief.md`:

```sh
sh "${CLAUDE_SKILL_DIR}/challenge-log.sh" new <slug> <repo-path>          # default pair
sh "${CLAUDE_SKILL_DIR}/challenge-log.sh" new <slug> <repo-path> --twin   # same model twice: the noise-floor control
sh "${CLAUDE_SKILL_DIR}/challenge-log.sh" new <slug> <repo-path> --fable  # opt-in; see the cost section
```

`new` draws which arm is A and which is B and hides the mapping. It pins the commit and prints the record directory. Do not read `.map`.

Fill in every section. The runner refuses a brief with an empty section, a `<fill in>` or `{TASK}` placeholder, or a Facts section that states no verification scope:

1. **Question** — a question, not a position to ratify.
2. **Facts** — with file:line or command output. **State the verification SCOPE.** "0 validators" and "0 validators under `src/parsers/`" are different claims, and the second exposes the gap the first hides. Say which files you did NOT read, so an arm knows where its own reading must start.
3. **The strongest case each way** — write the one you disagree with too.
4. **What evidence would settle this**, stated concretely.

Leave **Working rules** and **Output contract** as written: they make the arms read-only in intent and ask them not to name their model.

**Re-run every "verified" fact before dispatching.** A false premise poisons both arms identically, and two arms that inherit one bad premise will agree with each other confidently. Blindness protects against brand bias; nothing protects against the brief.

### Wording to leave out

These manufacture the agreement you are trying to test. The runner warns on most of them.

| Banned | Why |
|---|---|
| "the maintainer asked for YOUR ruling" | Grants authority; the reply performs authority |
| "a previous review correctly dismantled…" | Sets a track record to live up to |
| "you have been right before" / "the author has been wrong before" | Same, both directions |
| "rule on the merits, not from deference" | Naming deference invites the opposite performance |
| "the owner has delegated the call to you" | Makes disagreement insubordination |
| naming the other adjudicator, or that there is one | Invites differentiation for its own sake |
| "I think", "I believe", "we agree that" | A stated view and a shared view are among the strongest sycophancy drivers |

Say instead: "Answer the question below from the code. If the evidence does not settle it, say so." Adversarial framing about the *artifact* is fine ("try to break this design"). Authority framing about the *adjudicator* is what is banned.

## Step 3 — Dispatch

```sh
sh "${CLAUDE_SKILL_DIR}/challenge-run.sh" <slug>
```

A run takes about 2 to 5 minutes. **Start it in the background** (`run_in_background`) and wait for it to finish: a foreground command is cut off before the arms can.

The script launches both arms through the identical command, differing only in `--model`, with `--safe-mode` as the clean room, the brief on standard input, and the tools Read, Grep, Glob and Bash. It then runs the differential. Before it spends anything it refuses: an unfilled brief, a model string that is not a Claude model, a pair that could be one model, a Fable model without `--fable`, and a differential model that is also an arm.

Model strings may be IDs (`claude-opus-5-5`) or family aliases (`opus`). The pair is set per record with `CHALLENGE_MODEL_A` and `CHALLENGE_MODEL_B` when you run `new`; `--twin` doubles up `CHALLENGE_MODEL_A`. The differential model is `CHALLENGE_SYNTH_MODEL`, Sonnet 5.5 by default.

Three properties are load-bearing; do not work around them:

- **Both arms run through one command.** An arm run another way confounds a model comparison with a harness comparison.
- **`--safe-mode` is the clean room.** Without it an arm inherits the CLAUDE.md of its working directory, its skills and its hooks, and may answer in a persona.
- **The model is verified from the API's usage metadata**, never by asking the arm. The requested model, or an alias that resolves to it, must hold the most output tokens, or the answer is discarded. A silent fallback would leave a challenge that looks perfect and is worthless.

**Read-only is checked, not guaranteed.** The arms have no Write or Edit tool, but Bash can write. The runner compares the repository's HEAD and `git status` before and after and warns if either changed. It cannot see writes outside the repository.

### When a run does not finish cleanly

| Result | Meaning | Do |
|---|---|---|
| exit 2, before dispatch | A refusal or a model mismatch | Fix the cause. A mismatch means both arms were **billed**; the raw output is kept and `--reextract` re-reads it for free. |
| exit 3 | One arm failed. Its partner's answer is kept | Read it if useful. **Write no differential over one voice.** Dispatch again, or void the row. |
| exit 4 | Both arms answered; the differential failed | `challenge-run.sh <slug> --differential` re-runs just that step. |
| `BUDGET EXHAUSTED` | An arm hit the cap | Raise `CHALLENGE_ARM_BUDGET_USD` or narrow the brief. It is not a bug to hunt. |

`[claude-code:unrecognized_model]` in an arm's stderr is cosmetic. Only a `MODEL MISMATCH` means something.

## Step 4 — Read the differential; do not write it

The runner has already written `<record-dir>/differential.md`. A third model, **outside the pair**, read the brief and both answers with no tools and no repository, and **never saw which model wrote which answer**. It read them **in both orders** in two separate passes, so a position effect appears as disagreement between passes. It is told not to pick a winner.

Its sections: **Converged**; **Split: a check settles it**; **Split: a judgment call** (allowed to be empty); **Asymmetric coverage**, often the most useful; **Shared assumptions worth doubting**. The runner prints one `agreement:` value. If the two passes disagree, it prints `partial` and says why; that is a result, not noise.

Do not write the differential yourself. The party that formed the original conclusion is the worst party to judge whether it was challenged.

## Step 5 — Resolve the checkable splits yourself

Run every check in "a check settles it" **before** you report. A split that looks like a hard call is usually one arm wrong about a fact, and one `grep` ends it. Report the resolved answer and its evidence, not the split.

## Step 6 — Report

In this order:

1. **The answer** — what the challenge concluded, plainly.
2. **Converged** — what both agreed on, and whether by independent routes.
3. **Resolved** — splits you settled in step 5, with the evidence.
4. **Your call** — only what genuinely remains a decision. If nothing does, say so.
5. **Recommendation** — yours, and what would change your mind.

Show the arms' actual text for anything contested; your summary carries your prior. **Say plainly when the challenge did not settle it.** Two arms that both hedge is a result.

## Step 7 — One line, then done

```sh
sh "${CLAUDE_SKILL_DIR}/challenge-log.sh" note <slug> --stakes high --agreed no --note 'split on cache invalidation order'
```

`--agreed` says whether the two **substantive verdicts** matched: `yes`, `no`, or `partial`. **`partial` counts as a split**, as does `no`. Use the runner's `agreement:` line unless you have read the answers and know better. It is the only measure kept, because it is the only one that changes behaviour: if two arms almost never split on high-stakes questions, stop paying for the second dispatch.

```sh
sh "${CLAUDE_SKILL_DIR}/challenge-log.sh" status
```

shows the split rate per pairing with a 95% interval, and marks any pairing below 30 rows as directional. If the brief was defective, exclude the row: `challenge-log.sh void <slug> '<why>'`.

Records live in `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/challenge-log/`, or `$CHALLENGE_HOME`. The brief, both answers, the differential and the pinned commit stay on disk in the record dir.

## Quick reference

| Step | Action |
|---|---|
| 1 | Stakes: high / low / **none → stop** |
| 2 | `new <slug> <repo>`, fill the brief, state the scope, re-run every "verified" fact |
| 3 | `challenge-run.sh <slug>` in the background; tell the user the cost |
| 4 | Read `differential.md`; do not write it |
| 5 | Run every checkable split yourself |
| 6 | Report: answer, converged, resolved, your call, recommendation |
| 7 | `note --stakes --agreed`; `partial` is a split |

## Common mistakes

- **Dispatching without telling the user it spends quota or money.**
- **Adding `--fable` by default.** It is opt-in because of the price and the silent usage-credit billing.
- **Asking the user which answer they prefer.** Half of such picks measured style, not substance.
- **Writing the differential yourself,** or writing one after an exit 3.
- **Reporting a split you could have resolved** with one `grep`.
- **Padding "your call"** so the challenge looks worthwhile. Zero decisions left is a good outcome.
- **Treating agreement as proof.** Two arms can share a blind spot and inherit one false premise from the brief.
- **Calling a result settled at single-digit n.**

## Red flags — stop and fix

- The brief names the adjudicator or says another exists, or tells it that it decides
- The brief states your preferred answer before the evidence
- A fact marked verified that you did not re-run this session
- You know which model wrote which answer before reading the differential
- A model mismatch was reported and you are continuing anyway
- You are about to ask the user to choose between A and B

Measured split rates by pairing, the noise-floor control, and the cost figures behind the budget caps are in `reference.md`. Read it when choosing a pair or a cap, not on every run.
