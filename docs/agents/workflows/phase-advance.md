# Workflow: phase-advance

Move a subphase or a spec's status forward without leaving the docs inconsistent. Rules come from [`AGENTS.md`](../../../AGENTS.md) → *Status conventions*.

## Inputs

The subphase (e.g. `1.3`) or spec (e.g. `keyboard-and-insert`) and the new status, plus evidence: merged code, test results, a spike verdict, or a human decision.

## Steps

1. **Check the evidence against the exit criteria.** Read the phase's exit criteria in `ROADMAP.md` → *Phase plan* and the owning spec. If a criterion is not met, stop and report which one — do not flip the status. Device-only criteria without a recorded device result keep the subphase at 🟨 *Awaiting review / blocked*.
2. **Spec header(s).** Update `Implementation status` (and `Spec status` if the design changed), set `Last updated` to today, bump `(vN)` on a meaningful rework with a one-line note of what changed.
3. **ROADMAP *Specifications* table.** Mirror the header with the matching emoji: 🟥 Not started · 🟧 In progress · 🟨 Awaiting review / blocked · 🟩 Done · ⬛ Superseded.
4. **ROADMAP *Implementation Status* table.** Update the subphase row's status and its *Current state / next gate* text (what is done, what the next gate is).
5. **ROADMAP `Last updated`.** Set to today.
6. **AGENTS.md *Current repository state*.** Move items between *already wired up* and *not yet wired up* if the change affects them.
7. **Verify.** Run `scripts/agent-checks/run-all.sh`, then review the result with the `spec-keeper` role.

## Output

The list of files and rows changed, and any exit criterion that is still open.
