# context-nudge

A Claude Code prompt hook that tells you, and the model, how full the context window is. It says nothing until the window is 40 percent full or holds 100,000 tokens, speaks once on entry to each of three bands, and speaks on every prompt once compaction is close.

## The problem

A Claude Code session gets less reliable as its context window fills. Nothing announces it: answers get a little worse, earlier decisions get forgotten, and you notice only after the session has done an hour of doubtful work. The fix is cheap when it is early (finish the thread, compact, or hand off to a fresh session) and expensive when it is late.

The percentage is on screen if your status line shows it, but a number you have to look at is a number you stop looking at. And the model does not see your status line at all.

## What it does

On each prompt you submit, the hook looks up how full the window is and decides whether to speak:

- **Below the first band it is silent.** Most prompts in most sessions produce nothing.
- **On first entry to a band it speaks once**, to both of you: a one-line message you see, and one sentence in the model's context. It then stays quiet until the next band.
- **Close to compaction it speaks on every prompt.** At that level the repetition is the point.
- **The wording gets firmer with each band.**

The two messages differ on purpose. Yours carries the reading and the advice, which may suggest a handoff or a compact. The model's is one sentence of fact with no instruction in it: the reading, that it is information only, that a handoff is written only when you ask for one, and that a one-line suggestion to hand off or compact is the most it calls for. The tool never writes a handoff, and the model is told not to on the strength of a notice. A model that is handed advice reads a repeated warning as an order and wraps up work nobody asked it to wrap up.

For example, at 62 percent of a 200,000-token window you see

```
Context 62% used (124k of 200k tokens) - high. Finish what is open before starting something new. A handoff or a compact at the next clean break is worth considering.
```

and the model's context gets

```
CONTEXT NUDGE: the context window is 62% used (124k of 200k tokens) - high; this is information only, not an instruction to stop work, and a handoff is written only when the user asks for one, so a one-line suggestion to hand off or compact (the user may have the optional /handoff skill) is the most it calls for.
```

### Default bands and messages

A band is reached at its percentage of the context maximum **or** at its token count, whichever comes first. The percentage matters on a small window and the token count on a large one: a session holding 300,000 tokens is long whatever the size of the window around it.

| Band | Reached at | Label | Spoken | Message after the reading |
|---|---|---|---|---|
| none | below the first band | `ok` | never | (silent) |
| 1 | 40 percent or 100,000 tokens | `filling` | once | Still fine. Avoid starting a large new task in this session. |
| 2 | 60 percent or 200,000 tokens | `high` | once | Finish what is open before starting something new. A handoff or a compact at the next clean break is worth considering. |
| 3 | 80 percent or 300,000 tokens | `very high` | once | Quality over a window this full is likely dropping. Wrap up the current thread, then hand off or compact. |
| near compaction | within 10 percent of the compaction point | `critical` | every prompt | Compaction is close. Stop starting new work: land or park what is open now, then hand off or compact. |

What that gives on the two common windows:

| Window | Band 1 | Band 2 | Band 3 | Every prompt from |
|---|---|---|---|---|
| 200,000 tokens | 80,000 (40 percent) | 120,000 (60 percent) | 160,000 (80 percent) | 180,000 |
| 1,000,000 tokens | 100,000 (10 percent) | 200,000 (20 percent) | 300,000 (30 percent) | 900,000 |

The numbers are a judgement, not a published limit. No vendor states a point at which a model gets worse; the first notice is deliberately early.

### The context maximum and the compaction point

The context maximum is the model's real window, as Claude Code reports it in the status-line data (`context_window.context_window_size`). The tool never assumes a size: when none is known it reports nothing.

- Set `CONTEXT_NUDGE_WINDOW_SIZE` to state the maximum yourself. It replaces the reported size, and percentages are then worked out against it.
- The compaction point is where Claude Code compacts the conversation: the maximum, unless you have set a smaller auto-compact window, in which case set `CONTEXT_NUDGE_COMPACT_WINDOW` to that size in tokens.
- The every-prompt notices start `CONTEXT_NUDGE_REPEAT_MARGIN` percent below the compaction point.
- **A band that sits at or beyond that start is dropped.** With a 250,000-token compact window, for example, band 3 (300,000 tokens) can never be reached before compaction, so it is not announced; the every-prompt notices take over at 225,000.

If usage falls, after `/compact` for example, the hook re-arms silently at the lower band and announces the bands above it again as the window refills.

### Two halves

Claude Code does not give a prompt hook the context usage. The only place it reports usage is the JSON it sends to the status-line command. So the tool has two halves:

1. **The status-line half** records each session's usage in a small file every time the status line refreshes.
2. **The prompt hook** reads that file when you submit a prompt.

You need both. The status-line half comes in two forms that share one implementation: a complete, minimal status line for people who have none, and a cache writer that goes in front of a status line you already have.

Requirements: Claude Code, a POSIX shell and [`jq`](https://jqlang.org/), on macOS or Linux. Without `jq` the hook stays silent, the cache writer only passes its input through, and the status line shows `context-nudge: jq not found; install jq to see context usage`.

## Install

**Either way there are two things to set up: the prompt hook and the status-line half. The plugin delivers the hook only.** A Claude Code plugin cannot register a status line, so after installing the plugin you add one line to your settings by hand. Until you do, the hook has nothing to read and stays silent; it never reports a guessed figure.

Pick one way, not both, or the hook runs twice.

### As a Claude Code plugin

```sh
claude plugin marketplace add dmealing/dougs-ai-tools
claude plugin install context-nudge@dougs-ai-tools
```

Inside a session, the same two steps are `/plugin marketplace add dmealing/dougs-ai-tools` and `/plugin install context-nudge@dougs-ai-tools`.

The plugin registers the prompt hook itself, and nothing else. Add the status-line half by hand. Submit one prompt first: on its first run the hook copies the status-line scripts to `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/context-nudge/bin/`, a path that stays the same when the plugin is updated, and refreshes the copies once a day. Then add one of these to `~/.claude/settings.json`.

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

The thresholds:

| Variable | Default | Meaning |
|---|---|---|
| `CONTEXT_NUDGE_BAND1_PERCENT` | `40` | Band 1 is reached at this percentage of the context maximum. |
| `CONTEXT_NUDGE_BAND1_TOKENS` | `100000` | Band 1 is reached at this many tokens. |
| `CONTEXT_NUDGE_BAND2_PERCENT` | `60` | Band 2, as a percentage. |
| `CONTEXT_NUDGE_BAND2_TOKENS` | `200000` | Band 2, in tokens. |
| `CONTEXT_NUDGE_BAND3_PERCENT` | `80` | Band 3, as a percentage. |
| `CONTEXT_NUDGE_BAND3_TOKENS` | `300000` | Band 3, in tokens. |
| `CONTEXT_NUDGE_REPEAT_MARGIN` | `10` | The margin, as a percentage of the compaction point: the every-prompt notices start this far below it. |
| `CONTEXT_NUDGE_WINDOW_SIZE` | not set | The context maximum in tokens. Set it to override the size Claude Code reports, or to supply one when there is no status-line record; see [Limits](#limits). |
| `CONTEXT_NUDGE_COMPACT_WINDOW` | not set | The size in tokens of a smaller auto-compact window. Ignored unless it is below the context maximum. |
| `CONTEXT_NUDGE_MAX_AGE` | `3600` | The age in seconds beyond which a status-line record is ignored, so an out-of-date figure is never reported. `0` turns the check off. See [How the percentage is worked out](#how-the-percentage-is-worked-out). |

A band is reached by whichever of its two triggers comes first. Set one of them to `0` to turn that trigger off, and both to `0` to turn the band off. A value that is not a whole number is ignored and the default is used.

The words, and the rest:

| Variable | Default | Meaning |
|---|---|---|
| `CONTEXT_NUDGE_LABEL_OK` | `ok` | The label below band 1. Shown only by the status line. |
| `CONTEXT_NUDGE_LABEL_BAND1` | `filling` | The label in band 1. |
| `CONTEXT_NUDGE_LABEL_BAND2` | `high` | The label in band 2. |
| `CONTEXT_NUDGE_LABEL_BAND3` | `very high` | The label in band 3. |
| `CONTEXT_NUDGE_LABEL_CRITICAL` | `critical` | The label once the every-prompt notices have started. |
| `CONTEXT_NUDGE_JQ` | `jq` | The `jq` to run. Give a full path when Claude Code's `PATH` does not include it. `install.sh --write-settings` reads it too. |
| `CLAUDE_CONFIG_DIR` | `~/.claude` | Claude Code's own variable. The tool's files go in the `context-nudge` folder under it. |
| `NO_COLOR` | not set | Set it to any value for a status line without colour. |

Set the same values for the hook and the status line, or the two will label one reading differently. Setting them in one place, as above, does that.

## How the percentage is worked out

The status line and the hook cannot disagree: one function works out the percentage, the tokens in use and the band from the status-line JSON; the status line prints its result and the hook applies the same function to the same recorded values.

- When Claude Code reports `context_window.used_percentage`, that number is used, rounded down. It is read by that full path: the status-line input has other fields named `used_percentage`, under `rate_limits`, and those are never read. `null` means not known.
- When it does not (it can be `null` early in a session), or when `CONTEXT_NUDGE_WINDOW_SIZE` states a different maximum, the percentage is `context_window.total_input_tokens` divided by the maximum. Claude Code documents its own percentage as input tokens only, so the two agree.
- The token count is `context_window.total_input_tokens`; when only a percentage is reported, it is that percentage of `context_window.context_window_size`.
- When the usage or the maximum cannot be worked out, nothing is reported: the status line shows `context --` and the hook is silent.

The record carries the time it was written, and the hook ignores one older than `CONTEXT_NUDGE_MAX_AGE` seconds. The status line writes it after every reply, and the window does not change between a reply and your next prompt, so a record is normally exact however long you take to type. It goes out of date only when the status line has stopped running while the session went on, for example because the status-line half was removed. The default of one hour is long enough for a pause to read or think and short enough that a figure from an earlier sitting is not reported. A prompt sent after a longer pause gets no notice; the one after it does, because the reply refreshes the record.

These are the fields the tool depends on, as named in the Claude Code documentation for [hooks](https://code.claude.com/docs/en/hooks) and the [status line](https://code.claude.com/docs/en/statusline):

| Where | Field | Used for |
|---|---|---|
| Status-line input | `session_id` | Names the session's files. |
| Status-line input | `context_window.used_percentage` | The percentage. |
| Status-line input | `context_window.total_input_tokens` | The tokens in use: the token side of each band, and the percentage when none is reported. |
| Status-line input | `context_window.context_window_size` | The context maximum. |
| Status-line input | `model.display_name` | The model name in the status line. |
| Hook input | `session_id` | Finds the session's files. |
| Hook input | `transcript_path` | The transcript, read only when no status-line record exists. |
| Hook output | `systemMessage` | The message you see. |
| Hook output | `hookSpecificOutput.additionalContext` | The sentence the model sees, with `hookSpecificOutput.hookEventName` set to `UserPromptSubmit`. |

## Files

Everything is under `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/context-nudge/`:

| File | Written by | Holds |
|---|---|---|
| `<session>.usage` | the status-line half | The session's percentage, token count and window size, and when they were written. |
| `<session>.band` | the hook | The band last announced in the session. |
| `bin/` | `install.sh`, or the hook when run as a plugin | The scripts. |
| `settings-written` | `install.sh --write-settings` | Which settings entries it added, so `--uninstall` removes only those. |

A session id is used as a file name only when it is made of letters, digits, dots, hyphens and underscores and does not start with a dot; with any other id the scripts write and say nothing.

Once a day the hook deletes `.usage` and `.band` files that have not been written for 30 days, so the folder does not grow without bound. A new session has a new id, so `/clear` starts the bands again.

## Limits

- **The status-line half is required for an accurate percentage.** With only the hook installed, the hook is silent. It will not guess a window size: a 200,000-token guess is wrong by a factor of five on a 1,000,000-token model.
- **Headless mode has no status line.** In a non-interactive run (`claude -p`) nothing writes the record, so the hook is silent there unless you use the transcript fallback below.
- **The hook runs on every submitted prompt, typed or not.** A scheduled or looped prompt, and a sub-agent's result returning to the conversation, can each trigger it, so a notice can appear when nobody is at the keyboard.
- **The transcript fallback is a best effort.** If there is no status-line record, or the record is too old or holds no percentage yet, and you set `CONTEXT_NUDGE_WINDOW_SIZE`, the hook reads the token usage of the last reply from the transcript file named by `transcript_path`. The path is documented; the layout of the lines inside the file is not, and may change. The transcript can also lag the live conversation. When the hook finds no usage there it stays silent.
- **The reading is from the last reply, not the current prompt.** The status line refreshes after each reply, so the hook sees the window as it stood before the prompt you are submitting.
- **A notice is advice.** The tool never stops a prompt, never compacts and never writes a handoff. The model's sentence says it is not an instruction, and a model can still over-react to it.
- **The model's sentence is not shown in the transcript.** Claude Code adds it to the model's context without a visible entry; what you see is the one-line message.
- **Subagents are not measured.** The reading is the main conversation's.
- **Claude Code only.** Other agents have different hooks and are not supported.
- **Uninstalling the plugin leaves the `context-nudge` folder** with its script copies and per-session files. Delete it by hand.

## Tests

```sh
sh context-nudge/tests/run.sh
```

The path above is from the repository root; the script itself runs from anywhere. It feeds sample hook and status-line input (in `tests/fixtures/`) to the scripts and checks the silences, the one notice per band on a 200,000-token and a 1,000,000-token window, the repeats near compaction, every setting, the override and the dropped band, that the hook and the status line give the same percentage, the cases with no record, a stale record, a missing `jq` and the pruning. It tests `install.sh` against a throwaway directory, checks the shipped files for absolute home paths and for shell that stock macOS lacks, and runs `shellcheck` when it is installed.

## Related

[handoff](../handoff/) writes the file a fresh session continues from, and is the usual thing to do when this tool says the window is full. It is optional: context-nudge works without it, says "hand off or compact" either way, and never starts a handoff itself.

## Licence

Apache-2.0. See [LICENSE](../LICENSE).
