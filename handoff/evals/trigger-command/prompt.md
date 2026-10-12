---
description: The bare command. A slash command expands inline in a headless run and never calls the Skill tool, so a judge grades the reply.
tags: [should-trigger]
runs: 1
max_turns: 4
allowed_tools: [Read, Glob, Grep, Skill]
---

/handoff
