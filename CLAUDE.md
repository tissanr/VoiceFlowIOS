# Claude Code — pointer file

This repo is a **multi-agent project**. The canonical agent guide is [`AGENTS.md`](AGENTS.md). Read it first; it covers product, architecture, constraints, and the Phase 0 prerequisites.

`CLAUDE.md` exists because Claude Code looks for it by default. It contains only Claude-specific operational notes that genuinely don't apply to other agents. Product knowledge stays in `AGENTS.md`.

## Where to read

1. [`AGENTS.md`](AGENTS.md) — shared agent contract (product, constraints, do/don't).
2. [`ROADMAP.md`](ROADMAP.md) — canonical product spec, phase plan, exit criteria.
3. [`README.md`](README.md) — short reader-facing summary.

If `AGENTS.md` and this file disagree, **`AGENTS.md` wins**.

## Claude-specific notes

- Prefer the dedicated `Edit` / `Write` / `Read` tools over `cat` / `sed` / `echo` in Bash.
- Make independent tool calls in parallel.
- Never commit changes unless the user explicitly asks.
- Do not bypass git hooks (`--no-verify`) or skip signing without explicit user approval.
- When updating shared documentation (`AGENTS.md`, `ROADMAP.md`, `README.md`), keep the language **agent-neutral** — no "Claude says" framing in shared docs. Claude-specific instructions belong only in this file.
- The repo is shared with Codex (which reads `AGENTS.md`). When you change anything in `AGENTS.md`, assume Codex will read the next version cold; do not rely on conversation context to fill in gaps.

## What not to duplicate here

Do not copy product spec, architecture, App Group IDs, phase ordering, performance budgets, or constraints into this file. They live in `AGENTS.md` and `ROADMAP.md` so all agents see the same source of truth.
