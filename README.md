# dougs-ai-tools

Small, independent tools for Claude Code.

Each tool lives in its own folder with its own README, install steps and tests. Install only the ones you want. A tool that needs another says so in the table.

## Tools

| Tool | What it does | Status |
|---|---|---|
| [handoff](handoff/) | A skill that writes one Markdown file at the end of a session so a fresh session can continue the work: dead ends, misleading signals, state in flight, remaining work and the reasons behind decisions. | Available |
| [pickup](pickup/) | A skill that resumes from a handoff without you pasting its path. It finds the handoff for the current checkout and shows which one it chose, why, and what else it could have chosen, before loading it. Requires handoff. | Experimental |
| [context-nudge](context-nudge/) | A prompt hook that tells you and the model how full the context window is: silent until it is 40 percent full or holds 100K tokens, one notice on entry to each of three bands, and a notice on every prompt once compaction is close, so you can finish, compact or hand off in time. Needs `jq` and a one-line status-line addition. | Available |

## How this compares

These are not the only answers to the same problem, and for some situations they are not the best ones. What follows says what each alternative does, in a line, where it is the better choice, and where these tools differ. The descriptions come from each project's own README or source, read in October 2026; they change, so follow the link before relying on one.

### Built into Claude Code

Start here, because it costs nothing to install. See the [sessions](https://code.claude.com/docs/en/sessions) and [best practices](https://code.claude.com/docs/en/best-practices) pages.

- **`/compact` and auto-compaction** summarise the conversation in place and carry on. Better for one long sitting that is still going well.
- **`claude --continue`, `claude --resume` and `/resume`** reopen a saved conversation: `--continue` the most recent one in the current directory, `--resume` through a picker, `/resume` from inside a session. Sessions are saved continuously, so these also bring back a session that crashed. Better for ordinary resuming, and for crash recovery, which these tools do not attempt. What they bring back is the whole old conversation, which is the thing that was full. A handoff starts clean.
- **`/clear`** starts an empty conversation in the same directory. Better when nothing needs to carry over.

### Other handoff skills and commands

- [mattpocock/skills `handoff`](https://github.com/mattpocock/skills/blob/HEAD/skills/productivity/handoff/SKILL.md) ([its doc page](https://github.com/mattpocock/skills/blob/HEAD/docs/productivity/handoff.md)) is a short skill that only runs when you invoke it, writes one file to the operating system's temporary directory, redacts sensitive information, and takes a note about what the next session is for. Better when you want something very small, or when the work has to travel to another harness, directory or person. Its page says a file is needed only when something has to travel, and that `/compact` covers the ordinary case more often.
- [ykdojo/claude-code-tips](https://github.com/ykdojo/claude-code-tips) describes a `/handoff` command (part of its `dx` plugin) that checks for an existing `HANDOFF.md`, reads it, and creates or updates it with the goal, progress, what worked, what did not and next steps. Better for one stream of work per project.
- [ostikwhy-blip/claude-code-handoff-skill](https://github.com/ostikwhy-blip/claude-code-handoff-skill) verifies the state of the repository and writes a `HANDOFF.md` at the project root. The handoff skill here drew on it, with credit in [NOTICE](NOTICE). Better if you want the file in the repository.
- [HumanLayer's `create_handoff` and `resume_handoff`](https://github.com/humanlayer/humanlayer/blob/HEAD/.claude/commands/create_handoff.md) ([resume](https://github.com/humanlayer/humanlayer/blob/HEAD/.claude/commands/resume_handoff.md)) are commands from that project's own repository. They write timestamped files with YAML front matter under `thoughts/shared/handoffs/`, by ticket, and the resume command reads the plans a handoff links before proposing a course of action. Better if you already work from a `thoughts/` directory and tickets.
- [adrian-zielinski/session-handoff](https://github.com/adrian-zielinski/session-handoff) keeps one living file per topic in a `HANDOFF/` folder at the project root, with an index. `/handoff` updates the topic's file and `/pickup` reads the index and one topic. Closest in shape to these tools; it keeps the notes in the repository, where a team can share them. Its README is in Polish, with an English version linked.
- [Sting25/claude-code-handoff](https://github.com/Sting25/claude-code-handoff) writes a handoff and loads it automatically at the next session start. It also keeps a per-turn backup, saves a git-state snapshot on every clean exit, nudges you as context fills and signs each handoff. Better if you want saving and loading to happen without being asked.
- [thepushkarp/handoff](https://github.com/thepushkarp/handoff) appends timestamped entries to `docs/handoff/HANDOFF.md` with `/handoff:create`, resumes with `/handoff:resume`, and uses hooks to save before compaction and restore after it. Better if you want compaction made safe automatically.

### Frameworks

- [Continuous-Claude-v3](https://github.com/parcadei/Continuous-Claude-v3) is a whole development environment: skills, agents, hooks, a memory system and continuity ledgers, with YAML handoffs written automatically before compaction. Better if you want the environment, not just the handoff.
- [GSD](https://github.com/open-gsd/gsd-core) (moved from [gsd-build/get-shit-done](https://github.com/gsd-build/get-shit-done)) is a spec-driven phase loop in which each executor starts with a fresh context, so work is shaped to avoid long sessions in the first place. Better for planned, phased work.

Both ask you to adopt a workflow. The tools here do not.

### Context monitors and status lines

- [ccstatusline](https://github.com/sirmalloc/ccstatusline) and [claude-hud](https://github.com/jarrodwatts/claude-hud) draw configurable status lines, including context usage, always visible. Better if you want a gauge. They display; they do not say anything in the conversation.
- [f3kpclon/claude-code-handoff](https://github.com/f3kpclon/claude-code-handoff) replaces the status bar with context and quota bars, shows an operating-system dialog when context runs low (at 60 and 75 percent in its README), then writes a snapshot to disk and copies it to the clipboard. Better if you want a prompt dialog and a snapshot taken for you.

### Other agents

- [Amp's Handoff](https://ampcode.com/news/handoff) replaced compaction in that agent: you state a goal, and it drafts a prompt and a list of relevant files for a new thread.
- The [pi `handoff` extension](https://github.com/earendil-works/pi/blob/HEAD/packages/coding-agent/examples/extensions/handoff.ts) does something similar for pi, putting the generated prompt in the editor as a draft.

Both are built for their own agent and do not apply to Claude Code.

### Where these tools differ

- **handoff refuses to write while work that would die with the session is still running** (a local test run, a background job, a subagent), and says what is running. Work with an id a fresh session can re-attach to, such as a CI run, is allowed, and the file starts with the re-attach command.
- **Several streams per project, stored outside the repository.** Each is one file, `<project>/<stream>.md`; finished and superseded ones move to `done/`. Nothing can be committed by accident, and one project can have several threads in flight.
- **A handoff is rewritten, not edited,** and the previous version is kept in `done/`. A finished item cannot linger in the file, and dead ends are carried forward on purpose.
- **pickup chooses with a script and shows its reasons** before it reads anything, and flags a handoff that is stale, points at a missing branch or checkout, or whose pull request has merged. Ambiguous cases are put to you, not guessed.
- **context-nudge informs and does not instruct.** It speaks once on entry to each band, and on every prompt only once compaction is close. The sentence it gives the model says that a handoff is written only when the user asks.

### Where these tools are weaker

- **The handoff skill is long.** It is a few hundred lines of rules, against a few lines for the smallest alternatives, and a model has to read and follow them. The worked example and the list of mistakes load only on demand, but the gates do not.
- **Claude Code's own picker and `--continue` cover simple resuming.** pickup adds a layer, and earns it only when you keep several streams per project.
- **Nothing is saved automatically.** If a session crashes or is compacted by force, no handoff exists. Claude Code keeps the transcript, and `claude --resume` recovers the session.
- **Handoffs are local to one machine and written for Claude Code.** They do not travel to a colleague, another harness or another computer.
- **context-nudge needs `jq` and a status-line step.** The tools that only draw a gauge need neither.

## Install

The repository is a Claude Code plugin marketplace:

```sh
claude plugin marketplace add dmealing/dougs-ai-tools
claude plugin install handoff@dougs-ai-tools
claude plugin install pickup@dougs-ai-tools   # optional, experimental; declares handoff as a dependency
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

Apache-2.0. See [LICENSE](LICENSE). The handoff skill drew on an MIT-licensed project; its copyright line and permission notice are in [NOTICE](NOTICE).
