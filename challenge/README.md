# challenge

> **Experimental.** The brief rules, the scripts, the differential format and the log may change. Tell us what breaks.

A Claude Code skill for when you doubt a conclusion. It writes one neutral brief, sends it to **two independent headless Claude runs** that differ only in model, and has a **third model that cannot see which model wrote which answer** write a differential: where the two converged, where they split, which splits a check settles, which are a real judgment call, and what only one of them raised. It never picks a winner, and the only thing it logs is how often the two disagree.

## What it costs

**Every run starts two headless `claude -p` sessions and then a differential step of two calls on a third model.** There is no free run.

- On a **subscription login** that uses plan quota. With an **API key** it is metered money.
- The default pair is **Opus 5.5 and Opus 5**. Fable 5.1 is opt-in with `--fable`, because it costs **2.5 times as much per token as Opus 5.5** (the list prices are in [reference.md](skills/challenge/reference.md#cost)), and because **under `claude -p` Claude Code does not ask before a Fable request bills to usage credits**. A subscriber can be charged for Fable without a prompt. Check how your plan bills Fable before you pass `--fable`.
- Each arm has a budget cap (`--max-budget-usd`), $8 by default and $16 when a Fable model is in the pair. The CLI checks the cap against its own client-side estimate, and spend can pass it.
- In the author's own use, a run of two Opus models cost a little under $3 on average at list prices, and a pair with Fable about twice that. [reference.md](skills/challenge/reference.md) has the dated figures. They are one person's questions, not a benchmark.

The skill tells you the cost before it dispatches, and the scripts print it again. A challenge is for a call that is expensive to get wrong; for anything else, a single fresh review is cheaper.

## The problem

When you push back on a conclusion, the usual remedy is to ask the same model again, or to ask a model you trust more. Both tend to produce agreement and not information. An adjudicator told it is the authority, or reviewed by someone who already trusts it, performs that role. A second opinion is only evidence if it could have disagreed.

So this tool removes what lets a second opinion defer:

- **One neutral brief,** byte-identical for both arms, with the wording that manufactures agreement left out: authority, deference, a stated view, a mention of another reader. The runner warns on most of it.
- **A verification scope in code.** A brief must say which files were not read, because a false premise in a brief poisons both arms identically. The runner refuses a brief that does not, and refuses an untouched template.
- **Both arms through one command,** `--safe-mode` clean room, so a disagreement is a model difference and not two different system prompts.
- **The model is verified from the API's usage metadata,** not by asking the arm. A silent fallback to one model would leave a challenge that looks perfect and is worthless.
- **A blind differential** written by a model outside the pair, with no tools and no repository, which never sees which model wrote which answer and reads the answers in both orders.

## What it does

You type `/challenge`. The agent then:

1. **States the stakes in one line.** If both outcomes converge it stops and does not dispatch.
2. **Creates a record** with `challenge-log.sh new`, which draws which arm is A and which is B, hides the mapping and pins the commit.
3. **Writes the brief,** re-running every fact it marks verified.
4. **Runs `challenge-run.sh`,** which refuses a bad brief or bad model string before it spends anything, runs the arms in parallel, then writes `differential.md`.
5. **Resolves the splits a check settles,** so they never reach you.
6. **Reports** the answer, what converged, what it resolved, what remains your call, and a recommendation, with the arms' own text for anything contested.
7. **Logs one line.** The only measure kept is whether the two substantive verdicts agreed. `partial` counts as a split. `challenge-log.sh status` shows the split rate per pairing with a 95% interval, and marks any pairing under 30 rows as directional.

It starts only on `/challenge` or an explicit request for a cross-model second opinion. Disagreeing with it does not start it.

Requirements: Claude Code recent enough to have `--safe-mode` and to report `canonicalModel` in its JSON output (2.1.218 or later), `git`, `python3` and a POSIX shell, on macOS or Linux.

## Install

Pick one.

### As a Claude Code plugin

```sh
claude plugin marketplace add dmealing/dougs-ai-tools
claude plugin install challenge@dougs-ai-tools
```

Inside a session, the same steps are `/plugin marketplace add dmealing/dougs-ai-tools` and `/plugin install challenge@dougs-ai-tools`.

Plugin skills carry the plugin's name as a prefix, so the command is `/challenge:challenge`. The skill is allowed to run its own two scripts without a permission prompt; those are the only commands it pre-approves. The arms are separate `claude` processes that the script starts, so their tool use is not covered by that approval.

### With the install script

```sh
git clone https://github.com/dmealing/dougs-ai-tools.git
sh dougs-ai-tools/challenge/install.sh
```

This copies the skill and its scripts to `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills/challenge/`, and the command is `/challenge`. Run the script from the cloned repository: it uses code in the repository's `lib/` folder.

| Command | Effect |
|---|---|
| `sh install.sh` | Install. Does nothing if the same version is already there. Refuses to overwrite a file that differs. |
| `sh install.sh --force` | Install, replacing a file that differs. |
| `sh install.sh --uninstall` | Remove the skill. Refuses if an installed file differs from the shipped one. |

Records go to `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/challenge-log/`, or to `$CHALLENGE_HOME` when that is set. Each holds the brief, both answers, the differential and the pinned commit.

## Choosing the models and settings

| Variable | Default | What it does |
|---|---|---|
| `CHALLENGE_MODEL_A`, `CHALLENGE_MODEL_B` | `claude-opus-5-5`, `claude-opus-5` | The pair, read when you run `challenge-log.sh new`. An ID or a family alias (`opus`, `sonnet`, `haiku`, `fable`) works. |
| `CHALLENGE_SYNTH_MODEL` | `claude-sonnet-5-5` | The differential model. It must be outside the pair; an alias that could resolve to an arm's model is refused. |
| `CHALLENGE_ARM_BUDGET_USD` | 8 (16 with Fable) | The per-arm cap. |
| `CHALLENGE_ARM_TIMEOUT` | 900 | Seconds before an arm is killed. |
| `CHALLENGE_SYNTH_BUDGET_USD` | 4 | The cap for each differential call. |
| `CHALLENGE_SYNTH_TIMEOUT` | 300 | Seconds before a differential call is killed. |
| `CHALLENGE_SKIP_SCOPE_CHECK` | unset | Set to `1` to allow a brief that states no verification scope. Use it only when the brief truly has nothing unverified. |

`new --twin` puts the same model in both arms. Its split rate is the noise floor that makes every other rate mean something. `new --fable` allows a Fable model in the pair. A Fable model without `--fable` is refused, however it was configured.

Everything that can be checked is checked before the first paid call: an unfilled brief, a model string that is not a Claude model, a pair that could be one model, Fable without `--fable`, a differential model that is also an arm. A model alias or a `[1m]` suffix in the usage metadata is accepted. What cannot be checked in advance is whether the service answers with the model you asked for, and a mismatch there is caught from the usage metadata after the arms have run; both arms were billed by then, so the message says so and `--reextract` re-reads the saved output for free.

## How it compares

These descriptions come from each project's own README, source or documentation, read in October 2026. They change, so follow the link before relying on one.

### Built into Claude Code

- The [advisor](https://code.claude.com/docs/en/advisor) gives a model a second look at the work. It receives the full conversation, so it inherits your pushback and your framing; it is one opinion; and there is no differential or log. Better when you want a cheap check inside the session. Start there.
- `/code-review ultra`, managed Code Review and `claude-security` verify **code findings**. They do not challenge a conclusion or a design choice.

### Other tools

- [PAL MCP](https://github.com/BeehiveInnovations/pal-mcp-server) has a `consensus` tool that asks several models, whose answers cannot see each other and which have no tools; the calling agent synthesizes, knows the model names and recommends. Better when you want many vendors in one call.
- **PAL also has a tool named `challenge`, which is unrelated to this one.** Its job is to trigger automatically when you question or push back on something, and it calls no second model. This skill keeps the name `challenge` because that is what it does. If you install both, you will meet two different features with one name: this one runs only when you type `/challenge` and spends money when it does.
- [codex-plugin-cc](https://github.com/openai/codex-plugin-cc) runs Codex from Claude Code, read-only and ephemeral, and can gate a stop on its review. Better when you want a different vendor's model. Its README warns the stop gate may drain usage limits quickly, and it cannot show which model ran.
- [deliberation](https://github.com/antonbabenko/deliberation) pre-commits the controller blind, then asks an arbiter to produce exactly one verdict. Better when you want a ruling.
- [consult-llm](https://github.com/raine/consult-llm) sends one question to other models in parallel and tells the caller not to suggest solutions in the prompt. Better when you want other vendors cheaply.
- [Copilot CLI's Rubber Duck](https://docs.github.com/en/copilot/concepts/agents/copilot-cli/rubber-duck) uses a critic from a different model family and skips small, well-understood changes. Better in GitHub Copilot.

### Where this differs

- **It stops when nothing changes either way.** The stakes gate comes first, and none of the other tools listed here has an explicit "stop" gate that I found.
- **The brief is checked in code,** including its stated scope, and the wording that manufactures agreement is warned about.
- **The served model is verified** from the API's own usage metadata, and the run fails closed.
- **The differential is written by a model that is neither the controller nor an arm,** does not know which model wrote which answer, reads both orders, and is barred from picking a winner.
- **It logs disagreement and nothing else,** with an interval, and `partial` counts as a split.

### Where this is weaker

- **Claude-only.** Both arms and the differential are Claude models. That is the weakest diversity setting: errors are heavily shared inside one vendor, and this version has no arm from another vendor. Use one of the tools above when that is what you need.
- **It costs two sessions every time,** and a Fable pair costs more, as above.
- **Read-only is checked, not guaranteed.** The arms have no Write or Edit tool, but they have Bash, which can write. The runner compares the repository's HEAD and `git status` before and after and warns if either moved. It cannot see writes outside the repository.
- **The permission mode is not pinned,** so what an arm's Bash may run depends on your Claude Code settings. The arms read the live working tree, not the pinned commit.
- **The brief is the controller's.** Every fact in it is the agent's, and a false one reaches both arms. The scope check makes the gap visible; it does not close it.
- **The tests use a stub `claude`.** They check the scripts, not the CLI. The JSON fields and flags the scripts rely on are documented only lightly, so a Claude Code release can break a run before the tests notice.
- **The skill is not short:** about 90 lines, and the agent has to follow it. The measurements are in a second file that loads only on demand.

## Tests

```sh
sh challenge/tests/run.sh
```

They use a stub `claude` that records its calls and prints canned JSON; no model is called. They run in a throwaway home folder and git repository. Every tool at once: `sh tests/run.sh`.

## Licence

Apache-2.0. See [LICENSE](../LICENSE).
