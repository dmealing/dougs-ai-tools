# Fleet preset

For a supervisor that runs several Claude Code workers at once and wants to hear when one of them is filling its context window. The rule is: say nothing until 40 percent, then speak louder as the percentage climbs.

## The settings

Copy the `env` block from [`fleet-preset.settings.json`](fleet-preset.settings.json) into the `settings.json` the workers read (a user-level file, or a local one that is not committed):

```json
{
  "env": {
    "CONTEXT_NUDGE_BAND1_PERCENT": "40",
    "CONTEXT_NUDGE_BAND1_TOKENS": "0",
    "CONTEXT_NUDGE_BAND2_PERCENT": "60",
    "CONTEXT_NUDGE_BAND2_TOKENS": "0",
    "CONTEXT_NUDGE_BAND3_PERCENT": "80",
    "CONTEXT_NUDGE_BAND3_TOKENS": "0"
  }
}
```

The percentages are the defaults. What the preset changes is the token triggers: by default each band is also reached at 100,000, 200,000 and 300,000 tokens, and the lower trigger wins. On a 1,000,000-token window that makes the first notice come at 10 percent. Setting a token trigger to `0` turns it off, so every band is reached by percentage alone, on any window size. These are existing settings; the preset adds no code.

| Used | What the worker's terminal shows | Spoken |
|---|---|---|
| below 40 percent | nothing | never |
| 40 percent | `filling`: still fine, avoid starting a large new task | once |
| 60 percent | `high`: finish what is open; a handoff or a compact at the next clean break is worth considering | once |
| 80 percent | `very high`: wrap up the current thread, then hand off or compact | once |
| within 10 percent of the compaction point | `critical`: stop starting new work and land or park what is open | every prompt |

The notice needs the percentage to be known: install the status-line half, or set `CONTEXT_NUDGE_WINDOW_SIZE`. See the [README](README.md) for both, and for every other setting.

## What the notice does and does not do

The notice is shown to whoever is reading the worker's terminal. The worker's model gets one sentence of fact that says it is information only and that a handoff is written only when the user asks for one. The worker never writes a handoff on its own because of a notice. The ask has to come from outside, and in a fleet the supervisor is the one who asks.

## A worked example: Firstmate

[Firstmate](https://github.com/kunchenguid/firstmate) runs each worker as a coding agent in a visible terminal of its own, in a clean git worktree, and supervises it from a first-mate session. Its public documentation describes a way to send text to a worker (`bin/fm-send.sh`) and a way to replace a running worker with a new agent in the same worktree (`bin/fm-control.sh relaunch`); see its [agent control page](https://github.com/kunchenguid/firstmate/blob/main/docs/agent-control.md) for the exact calls. Firstmate has no feature that reads these notices. What follows is a procedure for the supervising agent, written with those two calls.

1. **The worker shows a notice** at 40 percent, then 60 and 80. The supervisor can see it when it reads the worker's terminal.
2. **The supervisor waits for a clean break.** Between tasks, or after a pull request is merged; not in the middle of a test run or a validation pipeline. A worker with something running that would die with the session refuses the handoff, which is the right answer, and the supervisor tries again later.
3. **The supervisor asks for a handoff**, naming what the next session is for: send the worker `/handoff next: <what the replacement worker should do>`. This is the ask the handoff skill waits for.
4. **The worker writes the file and stops.** Its last message is the path of the file.
5. **The supervisor relaunches the worker** in the same worktree, then sends `/pickup`, or `Read <path> and continue from it`. The new worker starts with an empty context and the dead ends, in-flight state and remaining work the old one wrote down.

Do not ask for a handoff at 40 percent merely because the notice appeared: at that level it means only that the window is worth watching. From 80 percent, do not put the break off for long. A handoff written at 85 percent is better than one written at 98.

## Tests

`sh context-nudge/tests/test-fleet-preset.sh` runs the preset through the real hook and checks the ladder at 15, 39, 40, 60, 80 and 95 percent on two window sizes.
