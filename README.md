# dougs-ai-tools

Small, independent tools for Claude Code and similar coding agents.

Each tool lives in its own folder with its own README, install steps and tests. Install only the ones you want. A tool that needs another says so in the table.

## Tools

| Tool | What it does | Status |
|---|---|---|
| [handoff](handoff/) | A skill that writes one Markdown file at the end of a session so a fresh session can continue the work: dead ends, misleading signals, state in flight, remaining work and the reasons behind decisions. | Available |
| [pickup](pickup/) | A skill that resumes from a handoff without you pasting its path. It finds the handoff for the current checkout and shows which one it chose, why, and what else it could have chosen, before loading it. Requires handoff. | Experimental |
| [context-nudge](context-nudge/) | A prompt hook that tells you and the model how full the context window is: silent until it is 40 percent full or holds 100K tokens, one notice on entry to each of three bands, and a notice on every prompt once compaction is close, so you can finish, compact or hand off in time. Needs `jq` and a one-line status-line addition. | Available |

## Install

The repository is a Claude Code plugin marketplace:

```sh
claude plugin marketplace add dmealing/dougs-ai-tools
claude plugin install handoff@dougs-ai-tools
claude plugin install pickup@dougs-ai-tools   # optional, experimental; needs handoff
claude plugin install context-nudge@dougs-ai-tools   # optional; see its README for the status-line step
```

Each tool's README also describes an install that does not use the plugin system.

## Tests

One command runs every tool's tests locally:

```sh
sh tests/run.sh
```

Each tool also carries its own, for example `sh handoff/tests/run.sh`. Code that the tools share (the install logic, the test helpers and the test runner) is in `lib/`.

## Licence

Apache-2.0. See [LICENSE](LICENSE).
