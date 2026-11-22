# Agent roles and workflows

Agent-neutral definitions used by any coding agent working in this repo. The rationale and the rule table live in [`docs/specs/agent-tooling.md`](../specs/agent-tooling.md); the overall contract is [`AGENTS.md`](../../AGENTS.md).

Before ending any task that changed files, run:

```sh
scripts/agent-checks/run-all.sh
```

Fix every `ERROR`. Report every `WARNING` to the human (PR description or final message).

## Roles

Review personas. Adopt one yourself or hand it to a sub-agent with the diff to review. Roles report findings; they edit only when asked.

- [`spec-keeper`](roles/spec-keeper.md) — spec headers, ROADMAP tables, cross-links, spec-vs-code drift.
- [`constraint-reviewer`](roles/constraint-reviewer.md) — iOS product constraints and the `Do not` list.
- [`privacy-guard`](roles/privacy-guard.md) — App-Review-sensitive changes; flags only.

## Workflows

Step-by-step procedures for recurring tasks.

- [`build-test`](workflows/build-test.md) — build and test, then run the checks.
- [`phase-advance`](workflows/phase-advance.md) — move a subphase or spec status forward.
