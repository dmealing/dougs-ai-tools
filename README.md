# dougs-ai-tools

Small, independent tools for Claude Code and similar coding agents.

Each tool lives in its own folder with its own README, install steps and tests. Install only the ones you want; none depends on another.

## Tools

| Tool | What it does | Status |
|---|---|---|
| [handoff](handoff/) | A skill that writes one Markdown file at the end of a session so a fresh session can continue the work: dead ends, misleading signals, state in flight, remaining work and the reasons behind decisions. | Available |

## Install

The repository is a Claude Code plugin marketplace:

```sh
claude plugin marketplace add dmealing/dougs-ai-tools
claude plugin install handoff@dougs-ai-tools
```

Each tool's README also describes an install that does not use the plugin system.

## Tests

Each tool carries its own tests, runnable locally with one command:

```sh
sh handoff/tests/run.sh
```

## Licence

Apache-2.0. See [LICENSE](LICENSE).
