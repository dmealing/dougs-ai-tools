---
description: A bare continue is not a request to pick up a handoff.
tags: [should-not-trigger]
runs: 1
plugins: ["../../../handoff", "../.."]
max_turns: 4
allowed_tools: [Read, Glob, Grep, Skill]
---

Continue.
