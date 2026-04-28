# Spec: Testing

> **Spec status:** Accepted (v1)
> **Implementation status:** Not started (test targets exist as stubs)
> **Last updated:** 2026-04-28
> **Owners:** iOS

Test plan for the spike phase, the MVP, and recurring regression checks.

---

## Phase 0 tests (spikes — produce written verdicts)

- Insert test text in: Apple Notes, Mail, Messages, Safari, a known masked field (e.g., credit-card field).
- Behavior in **Secure Field** and **Phone Pad**.
- Behavior after **Extension cold restart**.
- Behavior **without App Group access** (entitlement misconfigured) — `KeyboardState.noSharedAccess` shown.
- **Apple Speech** in German, English, mixed German / English.
- **In-keyboard recording** on iPhone 12 / 14 / 15 / 16 (or chosen device set) — peak memory + tap-to-record latency under [performance budgets](performance-and-memory.md).
- **App Group concurrency** under contention — interleaved writes from app + extension; verify the generation-counter protocol from [data-and-storage.md](data-and-storage.md).
- **`openURL` from extension** with and without Open Access.

---

## MVP acceptance tests (Phase 1 exit)

Functional:

- Start dictation from target app — **primary flow** end-to-end.
- Start dictation from target app — **fallback flow** end-to-end.
- Cancel recording mid-way; partial state cleaned up.
- Confirm recording → result reaches `PendingInsert`.
- Edit raw text before save (in containing app).
- Insert final text into the focused field.
- Reinsert latest dictation without a new recording (Flow D).
- Clipboard fallback fires in unsupported field (Flow E).
- Deny permission, retry; grant later, retry — flow recovers.
- Simulate **speech unavailable** (offline + locale not on-device) — clean error message, not silent failure.
- Simulate **corrupted / empty App Group store** — `KeyboardState.noSharedAccess` with setup hint.

Non-functional:

- VoiceOver completes primary flow end-to-end without sighted assistance.
- Dynamic Type at `accessibilityExtraExtraExtraLarge` — no clipped UI in the keyboard.
- Performance budgets met on iPhone 12 (or chosen baseline device) — see [performance-and-memory.md](performance-and-memory.md).

---

## Phase 4 regression tests

- Marked text / IME composition flow.
- RTL text insertion (no crash, logical order preserved).
- Selection replacement on every supported field type.
- Undo grouping — single undoable transaction per insert.
- Predictive override detection (post-insert context check).
- Masked / formatted fields — clipboard fallback fires.
- Performance budgets re-validated on the **lowest-supported** device.

---

## Test scaffolding

- Unit tests live in `VoiceFlowTests/` and exercise: state model transitions, `SharedStoreClient` concurrency protocol, postprocessing rules, insert-context spacing/capitalization rules, guardrails on the LLM adapter.
- UI tests live in `VoiceFlowUITests/` and exercise: onboarding flow, primary flow happy path, fallback flow happy path, clipboard fallback path.
- Snapshot tests for keyboard layouts at small / large / RTL / Dynamic-Type-XXXL — added in Phase 4.

---

## Cross-references

- What each MVP flow does end-to-end: [architecture.md](architecture.md)
- Insert edge-case checklist: [keyboard-and-insert.md](keyboard-and-insert.md)
- Concurrency invariants under test: [data-and-storage.md](data-and-storage.md)
