# context-nudge

A Claude Code prompt hook that tells you, and the model, how full the context window is. It says nothing below 40 percent, speaks once on entry to each band above that, and speaks on every prompt from 90.

## The problem

A Claude Code session gets less reliable as its context window fills. Nothing announces it: answers get a little worse, earlier decisions get forgotten, and you notice only after the session has done an hour of doubtful work. The fix is cheap when it is early (finish the thread, compact, or hand off to a fresh session) and expensive when it is late.

The percentage is on screen if your status line shows it, but a number you have to look at is a number you stop looking at. And the model does not see your status line at all.

## What it does

On each prompt you submit, the hook looks up how full the window is and decides whether to speak:

- **Below the first band it is silent.** Most prompts in most sessions produce nothing.
- **On first entry to a band it speaks once**, to both of you: a one-line message you see, and a matching notice in the model's context. It then stays quiet until the next band.
- **From the every-prompt threshold it speaks on every prompt.** At that level the repetition is the point.
- **The wording gets firmer as the percentage rises.**

The notice to the model says plainly that it is a readout for you, that on its own it is not an instruction to stop work or to write a handoff, and that the model may offer to hand off or compact in a single line and then wait for your answer. Without that, a model reads a repeated warning as an order and wraps up work nobody asked it to wrap up.

### Default bands and messages

Each message starts with the reading, for example `Context 62% used (124k of 200k tokens) - filling.` The rest depends on the percentage:

| Band | Label | Spoken | Message after the reading |
|---|---|---|---|
| below 40 | `ok` | never | (silent) |
| 40 | `filling` | once | Still fine. Avoid starting a large new task in this session. |
| 50 | `filling` | once | Still fine. Avoid starting a large new task in this session. |
| 60 | `filling` | once | Finish what is open before starting something new. |
| 70 | `high` | once | At the next clean break, consider a fresh session: hand off or compact. |
| 80 | `high` | once | Quality over a window this full is likely dropping. Wrap up the current thread, then hand off or compact. |
| 85 | `high` | once | Land what is in flight and move to a fresh session soon: hand off or compact. |
| 90 and up | `critical` | every prompt | Stop starting new work. Land or park what is open now, then hand off or compact. |

The band numbers are a judgement, not a published limit. No vendor states a percentage at which a model gets worse; 40 is a deliberately early first notice.

If usage falls, after `/compact` for example, the hook re-arms silently at the lower band and announces the bands above it again as the window refills.

### Two halves

Claude Code does not give a prompt hook the context usage. The only place it reports usage is the JSON it sends to the status-line command. So the tool has two halves:

1. **The status-line half** records each session's usage in a small file every time the status line refreshes.
2. **The prompt hook** reads that file when you submit a prompt.

You need both. The status-line half comes in two forms that share one implementation: a complete, minimal status line for people who have none, and a cache writer that goes in front of a status line you already have.

Requirements: Claude Code, a POSIX shell and [`jq`](https://jqlang.org/), on macOS or Linux. Without `jq` the hook stays silent, the cache writer only passes its input through, and the status line shows `context-nudge: jq not found; install jq to see context usage`.

## Install

Pick one way, not both, or the hook runs twice.

### As a Claude Code plugin

```sh
claude plugin marketplace add dmealing/dougs-ai-tools
claude plugin install context-nudge@dougs-ai-tools
```

Inside a session, the same two steps are `/plugin marketplace add dmealing/dougs-ai-tools` and `/plugin install context-nudge@dougs-ai-tools`.

The plugin registers the prompt hook itself. A plugin cannot set your status line, so add that half by hand. Submit one prompt first: on its first run the hook copies the status-line scripts to `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/context-nudge/bin/`, a path that stays the same when the plugin is updated, and refreshes the copies once a day. Then add one of these to `~/.claude/settings.json`.

If you have no status line:

```json
"statusLine": { "type": "command", "command": "sh ~/.claude/context-nudge/bin/context-nudge-statusline.sh" }
```

If you have one, see [Adding the cache writer to an existing status line](#adding-the-cache-writer-to-an-existing-status-line).

### With the install script

```sh
git clone https://github.com/dmealing/dougs-ai-tools.git
sh dougs-ai-tools/context-nudge/install.sh
```

This copies four scripts to `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/context-nudge/bin/` and prints the two settings entries that turn them on, with the real paths filled in:

```json
"hooks": {
  "UserPromptSubmit": [
    { "hooks": [ { "type": "command", "command": "sh '<config>/context-nudge/bin/context-nudge-hook.sh'" } ] }
  ]
},
"statusLine": { "type": "command", "command": "sh '<config>/context-nudge/bin/context-nudge-statusline.sh'" }
```

It does not touch your settings file unless you ask. Run the script from the cloned repository: it uses code in the repository's `lib/` folder.

| Command | Effect |
|---|---|
| `sh install.sh` | Install the scripts and print the settings entries. Does nothing to a script that is already up to date. Refuses to overwrite one that differs. |
| `sh install.sh --write-settings` | Install, then add the two entries to `settings.json` with `jq`. |
| `sh install.sh --force` | Install, replacing a script that differs. |
| `sh install.sh --uninstall` | Remove the scripts, and the settings entries a `--write-settings` run added. Refuses if an installed script differs from the shipped one. |
| `sh install.sh --uninstall --force` | Remove the scripts even if they were modified. |

What `--write-settings` does, exactly:

- It writes a backup first, beside the settings file, named `settings.json.context-nudge-backup-<date>-<time>`. A settings file that does not exist yet is created and needs no backup.
- It adds the hook to any `UserPromptSubmit` hooks you already have, and leaves every other setting as it was.
- **It refuses if a different status line is already set.** Nothing is written; it prints your current command and the one-line change below. Make that change, run it again, and it adds the hook and keeps your status line.
- It changes nothing, and writes no backup, when both entries are already there.
- It stops without writing if `jq` is missing or the settings file is not a JSON object.

`--uninstall` removes from the settings only the entries a `--write-settings` run added, and only while they still hold the exact command it wrote; it backs the file up first. Entries you added by hand are left for you to remove, and it says so. The per-session files the hook wrote stay in `context-nudge/`; delete that folder when you no longer want them.

## Adding the cache writer to an existing status line

`context-nudge-cache.sh` reads the status-line JSON on standard input, records the session's usage, and writes the same JSON to standard output unchanged. It prints nothing of its own. So it goes in front of what you have. Either change the command in `settings.json`:

```json
"statusLine": {
  "type": "command",
  "command": "sh ~/.claude/context-nudge/bin/context-nudge-cache.sh | my-status-line.sh"
}
```

or change the line in your own script that reads the input:

```sh
input=$(sh ~/.claude/context-nudge/bin/context-nudge-cache.sh)   # was: input=$(cat)
```

Your status line looks exactly as it did.

## Settings

Every setting is an environment variable. Set them where Claude Code will pass them on: in your shell profile, or under `"env"` in `settings.json`.

| Variable | Default | Meaning |
|---|---|---|
| `CONTEXT_NUDGE_BANDS` | `40 50 60 70 80 85` | The bands, separated by spaces or commas. The hook speaks once on first entry to each. The lowest is the first notice. Entries at or above the every-prompt threshold are ignored. |
| `CONTEXT_NUDGE_REPEAT_AT` | `90` | The every-prompt threshold: from this percentage the hook speaks on every prompt, with the label `critical`. |
| `CONTEXT_NUDGE_HIGH_AT` | `70` | The percentage from which the label is `high`. |
| `CONTEXT_NUDGE_LABEL_OK` | `ok` | The label below the first band. Shown only by the status line. |
| `CONTEXT_NUDGE_LABEL_FILLING` | `filling` | The label from the first band. |
| `CONTEXT_NUDGE_LABEL_HIGH` | `high` | The label from `CONTEXT_NUDGE_HIGH_AT`. |
| `CONTEXT_NUDGE_LABEL_CRITICAL` | `critical` | The label from `CONTEXT_NUDGE_REPEAT_AT`. |
| `CONTEXT_NUDGE_WINDOW_SIZE` | not set | The context window size in tokens. Used only when no status-line record exists; see [Limits](#limits). |
| `CONTEXT_NUDGE_JQ` | `jq` | The `jq` to run. Give a full path when Claude Code's `PATH` does not include it. `install.sh --write-settings` reads it too. |
| `CLAUDE_CONFIG_DIR` | `~/.claude` | Claude Code's own variable. The tool's files go in the `context-nudge` folder under it. |
| `NO_COLOR` | not set | Set it to any value for a status line without colour. |

The bands decide **when** the hook speaks. The wording follows the percentage and never runs ahead of the label: it steps at 60 while the label is `filling`, at `CONTEXT_NUDGE_HIGH_AT`, at 80 and 85 while the label is `high`, and at `CONTEXT_NUDGE_REPEAT_AT`. A value that is not a whole number is ignored and the default is used.

Set the same values for the hook and the status line, or the two will label one percentage differently. Setting them in one place, as above, does that.

## How the percentage is worked out

The status line and the hook cannot disagree: one function works the percentage out from the status-line JSON, the status line prints its result and the hook reads the same result from the file.

- When Claude Code reports `context_window.used_percentage`, that number is used, rounded down.
- When it does not (it can be `null` early in a session), the percentage is `context_window.total_input_tokens` divided by `context_window.context_window_size`. Claude Code documents its own percentage as input tokens only, so the two agree.
- When neither can be worked out, the percentage is unknown: the status line shows `context --` and the hook is silent.

These are the fields the tool depends on, as named in the Claude Code documentation for [hooks](https://code.claude.com/docs/en/hooks) and the [status line](https://code.claude.com/docs/en/statusline):

| Where | Field | Used for |
|---|---|---|
| Status-line input | `session_id` | Names the session's files. |
| Status-line input | `context_window.used_percentage` | The percentage. |
| Status-line input | `context_window.total_input_tokens` | The token count shown, and the percentage when none is reported. |
| Status-line input | `context_window.context_window_size` | The window size shown, and the percentage when none is reported. |
| Status-line input | `model.display_name` | The model name in the status line. |
| Hook input | `session_id` | Finds the session's files. |
| Hook input | `transcript_path` | The transcript, read only when no status-line record exists. |
| Hook output | `systemMessage` | The message you see. |
| Hook output | `hookSpecificOutput.additionalContext` | The notice the model sees, with `hookSpecificOutput.hookEventName` set to `UserPromptSubmit`. |

## Files

Everything is under `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/context-nudge/`:

| File | Written by | Holds |
|---|---|---|
| `<session>.usage` | the status-line half | The session's percentage, token count and window size. |
| `<session>.band` | the hook | The highest band already announced in the session. |
| `bin/` | `install.sh`, or the hook when run as a plugin | The scripts. |
| `settings-written` | `install.sh --write-settings` | Which settings entries it added, so `--uninstall` removes only those. |

Once a day the hook deletes `.usage` and `.band` files that have not been written for 30 days, so the folder does not grow without bound. A new session has a new id, so `/clear` starts the bands again.

## Limits

- **The status-line half is required for an accurate percentage.** With only the hook installed, the hook is silent. It will not guess a window size: a 200,000-token guess is wrong by a factor of five on a 1,000,000-token model.
- **The transcript fallback is a best effort.** If there is no status-line record, or the record holds no percentage yet, and you set `CONTEXT_NUDGE_WINDOW_SIZE`, the hook reads the token usage of the last reply from the transcript file named by `transcript_path`. The path is documented; the layout of the lines inside the file is not, and may change. The transcript can also lag the live conversation. When the hook finds no usage there it stays silent.
- **The reading is from the last reply, not the current prompt.** The status line refreshes after each reply, so the hook sees the window as it stood before the prompt you are submitting.
- **A notice is advice.** The tool never stops a prompt, never compacts and never writes a handoff. The model is told not to treat the notice as an instruction, and a model can still over-react to it.
- **The model's notice is not shown in the transcript.** Claude Code adds it to the model's context without a visible entry; what you see is the one-line message.
- **Subagents are not measured.** The reading is the main conversation's.
- **Claude Code only.** Other agents have different hooks and are not supported.
- **Uninstalling the plugin leaves the `context-nudge` folder** with its script copies and per-session files. Delete it by hand.

## Tests

```sh
sh context-nudge/tests/run.sh
```

The path above is from the repository root; the script itself runs from anywhere. It feeds sample hook and status-line input (in `tests/fixtures/`) to the scripts and checks the silences, the one notice per band, the repeats, the settings, that the hook and the status line give the same percentage, the cases with no record, a missing `jq` and the pruning. It tests `install.sh` against a throwaway directory, checks the shipped files for absolute home paths and for shell that stock macOS lacks, and runs `shellcheck` when it is installed.

## Related

[handoff](../handoff/) writes the file a fresh session continues from, and is the usual thing to do when this tool says the window is full. It is optional: context-nudge works without it, and says "hand off or compact" either way.

## Licence

Apache-2.0. See [LICENSE](../LICENSE).
