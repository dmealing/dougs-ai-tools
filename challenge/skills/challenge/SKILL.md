---
name: challenge
description: Experimental. Get a second opinion on a conclusion: one neutral brief goes to two Claude models in separate headless sessions, and you read a blind differential of their answers. Each run uses plan quota or metered money.
disable-model-invocation: true
allowed-tools:
  - Bash(sh ${CLAUDE_SKILL_DIR}/challenge-log.sh *)
  - Bash(sh "${CLAUDE_SKILL_DIR}/challenge-log.sh" *)
  - Bash(sh ${CLAUDE_SKILL_DIR}/challenge-run.sh *)
  - Bash(sh "${CLAUDE_SKILL_DIR}/challenge-run.sh" *)
---

# Challenge

Experimental: the scripts and the log format may change.

A challenge sends one neutral brief to two independent arms and gives the user a differential of where they converged, where they split and what only one raised. A second opinion is evidence only if it could have disagreed, so the brief and the comparison are built so that neither arm is steered toward agreement.

## Cost: tell the user before you dispatch

A run is two headless `claude -p` sessions (the arms) plus two calls on a third, cheaper model (the differential). On a subscription that uses plan quota; with an API key it is metered money. The per-arm cap is the CLI's own estimate and can be passed. Say this in one line before you start.

The default pair is Opus 5.5 and Opus 5. Add `--fable` only when the user asked for it: Fable 5.1 costs 2.5 times Opus 5.5 per token, and under `-p` Claude Code bills Fable to usage credits without asking. Say so when you use it.

## 1. Stakes

Ask what changes if the conclusion is wrong: `high` (real work, a shipped defect, hard to reverse), `low` (caught cheaply), or `none` (both answers lead to the same place). At `none`, say so and do not dispatch. The log counts only `high` rows.

## 2. The brief

```sh
sh "${CLAUDE_SKILL_DIR}/challenge-log.sh" new <slug> <repo-path>          # default pair
sh "${CLAUDE_SKILL_DIR}/challenge-log.sh" new <slug> <repo-path> --twin   # same model twice: the noise-floor control
sh "${CLAUDE_SKILL_DIR}/challenge-log.sh" new <slug> <repo-path> --fable  # only when asked
```

`new` pins the commit, writes `<record-dir>/brief.md` and hides which model is arm A. Do not read `.map`.

Fill every section; the runner refuses empty sections and placeholders:

1. **Question**: a question, not a position to ratify.
2. **Facts**, with file:line or command output, and the verification scope: "0 validators under `src/parsers/`", not "0 validators". Name the files you did not read.
3. **The strongest case each way**, including the one you disagree with.
4. **What evidence would settle it**, concretely.

Re-run every fact you call verified before dispatching: a false premise reaches both arms, and they will agree on it. Leave **Working rules** and **Output contract** as written.

Write about the artifact, not the arms. Adversarial framing of the work is fine ("try to break this design"). Leave out anything that gives an arm authority, a track record or a side to take: that it decides, that it has been right before, that another reviewer exists, or what you or the user believe ("I think", "we agree"). Each of these produces agreement instead of information, and the runner warns on most of them. A good default is: "Answer the question below from the code. If the evidence does not settle it, say so."

## 3. Dispatch

```sh
sh "${CLAUDE_SKILL_DIR}/challenge-run.sh" <slug>
```

Run it in the background (`run_in_background`) and wait: a run takes 2 to 5 minutes, longer than a foreground command is allowed. The script runs both arms through one identical command in `--safe-mode`, read-only in intent, checks from the API usage metadata that each arm ran the requested model, and then writes the differential. Do not work around any of that: a mismatch in harness or model makes the comparison worthless. `CHALLENGE_MODEL_A`, `CHALLENGE_MODEL_B` (set at `new`) and `CHALLENGE_SYNTH_MODEL` choose the models.

| Result | Meaning | Do |
|---|---|---|
| exit 2 | Refused before dispatch, or a model mismatch | Fix the cause. After a mismatch both arms were billed; `--reextract` re-reads their output for free. |
| exit 3 | One arm failed | Its partner's answer is kept. Write no differential over one voice: dispatch again or void the row. |
| exit 4 | The differential failed | `challenge-run.sh <slug> --differential` re-runs only that step. |
| `BUDGET EXHAUSTED` | An arm hit its cap | Raise `CHALLENGE_ARM_BUDGET_USD` or narrow the brief. |

`[claude-code:unrecognized_model]` in an arm's stderr is cosmetic; only `MODEL MISMATCH` matters. The runner warns if the repository changed during the run, but it cannot see writes elsewhere.

## 4. Read the differential and settle what a check can settle

Read `<record-dir>/differential.md`. A model outside the pair wrote it without knowing which model wrote which answer, reading them in both orders; `agreement: partial` means the passes disagreed, which is a result. Do not write or rewrite the differential yourself: you formed the original conclusion.

Run every check listed under "a check settles it" before you report. Most splits that look like judgment calls are one arm wrong about a fact.

## 5. Report

1. The answer, plainly, including when the challenge did not settle it.
2. What both arms agreed on, and whether by different routes.
3. Splits you settled, with the evidence.
4. What is still the user's call. Often nothing; say so.
5. Your recommendation, and what would change your mind.

Quote the arms' own text for anything contested: your summary carries your prior. Do not ask the user to pick the answer they prefer: that measures style, not substance.

## 6. Log it

```sh
sh "${CLAUDE_SKILL_DIR}/challenge-log.sh" note <slug> --stakes high --agreed no --note 'split on cache invalidation order'
sh "${CLAUDE_SKILL_DIR}/challenge-log.sh" status        # split rate per pairing, with a 95% interval
sh "${CLAUDE_SKILL_DIR}/challenge-log.sh" void <slug> '<why>'   # a defective brief
```

`--agreed` is whether the substantive verdicts matched: `yes`, `no` or `partial`, and `partial` counts as a split. Use the runner's `agreement:` value unless you read the answers and know better. The split rate is the only measure kept because it decides whether the second dispatch is worth paying for.

Records live in `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/challenge-log/`, or `$CHALLENGE_HOME`. `reference.md` has measured split rates by pairing and the cost figures behind the caps; read it when choosing a pair or a cap.
