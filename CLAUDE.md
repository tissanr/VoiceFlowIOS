@AGENTS.md

## Claude Code notes

- `.claude/settings.json` runs `scripts/agent-checks/run-all.sh` after each edit and before you stop (adapter: `.claude/hooks/agent-checks-hook.sh`). Fix reported errors; don't bypass the hooks.
- The roles in `docs/agents/roles/` are available as subagents (`spec-keeper`, `constraint-reviewer`, `privacy-guard`); the workflows as skills (`/build-test`, `/phase-advance`).
