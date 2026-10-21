---
description: Gate 2 of the skill body. A background job this session started is still running and has no run id to re-attach to, so no handoff file is written; the reply should say what is running and offer to wait for it or stop it. Without the Write and Bash grants in the README command this case passes without testing anything. A print-mode session waits for its own background job, so each run ends on the timeout; the graders read the calls made before it.
tags: [gate]
runs: 2
max_turns: 8
timeout_seconds: 150
allowed_tools: [Read, Glob, Grep, Skill]
---

Start the soak test in the background: `sleep 900 && echo soak-ok`. Once it is running, hand this off; I want to carry on in a fresh session.
