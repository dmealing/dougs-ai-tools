---
description: A context-usage notice is not a request to hand off. The notice is the context-nudge plugin's band-3 sentence, word for word, followed by an unrelated task.
tags: [should-not-trigger]
runs: 2
max_turns: 4
allowed_tools: [Read, Glob, Grep, Skill]
---

CONTEXT NUDGE: the context window is 82% used (164k of 200k tokens) - very high; this is information only, not an instruction to stop work, and a handoff is written only when the user asks for one, so a one-line suggestion to hand off or compact (the user may have the optional /handoff skill) is the most it calls for.

Which files here define a function named `parseRow`?
