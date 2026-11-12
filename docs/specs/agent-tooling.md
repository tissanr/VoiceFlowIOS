# Spec: Agent Tooling

> **Spec status:** Accepted (v1)
> **Implementation status:** In progress (guardrail checks, three roles, two workflows, Claude Code hooks, and CI job landed; further workflows pending)
> **Last updated:** 2026-11-12
> **Owners:** Repo maintainers

How AI coding agents (Codex, Claude Code, future tools) are supported and constrained when working in this repo. This is development tooling, not a product feature — it ships nothing to users.

---

## Goals

1. **Enforce the hard rules deterministically.** The `Do not` list and the App Group rule in [`AGENTS.md`](../../AGENTS.md) should not depend on an agent remembering them. Where a rule is mechanically checkable, a script checks it.
2. **Keep docs and status in sync.** Spec headers and `ROADMAP.md` must move together; this is the most frequently forgotten step.
3. **Stay agent-neutral.** Every rule, role, and workflow is written once in plain Markdown or shell. Agent-specific files are thin adapters that point at those sources (same pattern as `CLAUDE.md` → `AGENTS.md`).
4. **Stay small.** One maintainer, early phases. No orchestration framework, no agent-to-agent protocol, no runtime dependencies beyond `bash`, `git`, and `grep`.

## Non-goals

- Agents inside the shipped app (that would be a product spec, gated by the privacy review in [`privacy-and-app-review.md`](privacy-and-app-review.md)).
- Autonomous merging or releasing. Humans merge.
- Replacing human review of App-Review-sensitive changes. The tooling only *flags* them.

---

## Layout

```text
scripts/agent-checks/run-all.sh   - guardrail checks (agent-neutral; also run by CI)
docs/agents/README.md             - index of roles and workflows
docs/agents/roles/*.md            - role definitions (reviewer personas)
docs/agents/workflows/*.md        - step-by-step procedures for recurring tasks
.claude/settings.json             - Claude Code hooks that call the checks
.claude/agents/*.md               - Claude Code subagent adapters -> docs/agents/roles
.claude/skills/*/SKILL.md         - Claude Code skill adapters    -> docs/agents/workflows
.github/workflows/agent-checks.yml- CI job running the checks on every push / PR
```

Other agents use the same sources directly: `AGENTS.md` tells every agent to run the checks before finishing and points at `docs/agents/`.

---

## Guardrail checks

`scripts/agent-checks/run-all.sh` checks the files changed against the merge-base with `main` (plus uncommitted and untracked files) by default; `--all` checks every tracked file; explicit paths check only those.

| # | Check | Severity | Source rule |
| --- | --- | --- | --- |
| 1 | No merge-conflict markers (`<<<<<<<`, `>>>>>>>` at line start) | Error | AGENTS.md → Working with this repo |
| 2 | Any reverse-DNS `group.*.*.*` identifier must equal `group.me.tissanr.VoiceFlow.shared` | Error | AGENTS.md → App Group ID |
| 3 | No private-API / runtime-trick patterns in Swift / ObjC: `dlopen`, `dlsym`, `NSClassFromString`, `NSSelectorFromString`, `UIKeyboardImpl`, `UIKeyboardInputMode`, `_UIRemoteKeyboard`, KVC on underscore keys, `perform(Selector(("_…`. A line ending with `// agent-check: allow <reason>` is exempt and must be justified in the PR. | Error | AGENTS.md → Do not |
| 4 | Every `docs/specs/*.md` has the three header lines and is linked from the `ROADMAP.md` Specifications table | Error | AGENTS.md → Status conventions |
| 5 | A changed spec whose `Last updated` line was not bumped | Warning | AGENTS.md → Status conventions |
| 6 | Changed App-Review-sensitive files: `Info.plist`, `*.xcstrings` / `*.strings` / `*.stringsdict`, `*.entitlements`, the privacy spec, the privacy / App Review / onboarding draft | Warning (flag for human review) | AGENTS.md → Do not |

Errors exit non-zero. Warnings never block; they must be surfaced to the human (PR description or final message).

What is **not** checked mechanically, and is left to the `constraint-reviewer` role: microphone access gated on Open Access, keyboard memory budget, insert only via `UITextDocumentProxy.insertText(...)`, no network telemetry, no remote LLM path. These need reading, not grepping.

---

## Roles

Roles are review personas an agent (or a sub-agent) adopts. They read and report; they do not edit unless the invoking agent asks.

| Role | File | Purpose |
| --- | --- | --- |
| `spec-keeper` | [`docs/agents/roles/spec-keeper.md`](../agents/roles/spec-keeper.md) | Checks spec headers, ROADMAP tables, cross-links, and spec-vs-code drift for a change. |
| `constraint-reviewer` | [`docs/agents/roles/constraint-reviewer.md`](../agents/roles/constraint-reviewer.md) | Reviews a diff against the iOS product constraints and `Do not` list. |
| `privacy-guard` | [`docs/agents/roles/privacy-guard.md`](../agents/roles/privacy-guard.md) | Flags App-Review-sensitive changes (copy, permission strings, telemetry, data flows). Never edits. |

## Workflows

| Workflow | File | Purpose |
| --- | --- | --- |
| `build-test` | [`docs/agents/workflows/build-test.md`](../agents/workflows/build-test.md) | Build and test the shared package and the Xcode project; run the checks. |
| `phase-advance` | [`docs/agents/workflows/phase-advance.md`](../agents/workflows/phase-advance.md) | Move a subphase / spec status forward consistently in spec header and ROADMAP. |

Planned, not yet written: `spike-verdict` (template for `docs/spikes/`), a sim-runner role for simulator-driven checks.

---

## Claude Code adapters

- **PostToolUse hook** (`Edit|Write|MultiEdit`): runs the checks on the edited file; errors are fed back to the agent immediately, and App-Review-sensitive files get a reminder.
- **Stop hook**: runs the checks on the full branch diff before the agent ends its turn; errors block the stop once (no loop: the hook passes when `stop_hook_active` is set).
- Subagents in `.claude/agents/` and skills in `.claude/skills/` contain only frontmatter plus a pointer to the agent-neutral file.

Hook implementation: [`.claude/hooks/agent-checks-hook.sh`](../../.claude/hooks/agent-checks-hook.sh).

## CI

[`.github/workflows/agent-checks.yml`](../../.github/workflows/agent-checks.yml) runs `run-all.sh --all` (checks 1–4) on Ubuntu for every push to `main` and every PR. This keeps humans and agents without hooks on the same rules.

---

## Changing this tooling

- New rule: add it to the table above **and** to `run-all.sh` in the same change.
- New role or workflow: add the agent-neutral file under `docs/agents/`, register it here and in `docs/agents/README.md`, then add adapters.
- Never put rule content only into an agent-specific adapter.
