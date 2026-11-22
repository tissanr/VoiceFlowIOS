---
name: phase-advance
description: "Move a VoiceFlow iOS subphase or spec status forward consistently (spec header, ROADMAP tables, AGENTS.md repository state), checking exit criteria first. Arguments - the subphase or spec and the new status."
---

Follow `docs/agents/workflows/phase-advance.md` step by step for: $ARGUMENTS

That file is the agent-neutral source of truth. Finish by running `scripts/agent-checks/run-all.sh` and the `spec-keeper` subagent.
