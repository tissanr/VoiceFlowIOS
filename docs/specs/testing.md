# Spec: Testing

> **Spec status:** Accepted (v2)
> **Implementation status:** In progress (`VoiceFlowShared` unit tests and App Group contention spike harness exist)
> **Last updated:** 2026-05-15
> **Owners:** iOS

Test plan for the spike phase, the MVP, and recurring regression checks.

---

## Required iOS test versions

VoiceFlow targets **iOS 17.0+**. Testing is version-first rather than phone-model-first because the riskiest behavior is controlled by iOS custom-keyboard, Open Access, Speech, and audio-session behavior.

| Tier | iOS version | Environment | Required for | Notes |
| --- | --- | --- | --- | --- |
| Minimum supported | iOS 17.x, latest available 17 patch preferred | Physical iPhone if available; otherwise TestFlight / borrowed-device pass before Phase 1 sign-off | Deployment-target compatibility, `SFSpeechRecognizer`, App Group access, keyboard lifecycle | This is the baseline selected by [../spikes/min-ios-investigation.md](../spikes/min-ios-investigation.md). Do not claim iOS 17 compatibility from an iOS 26 simulator run alone. |
| Current shipping | iOS 26.x, latest available patch | Physical iPhone for microphone / Open Access / memory; simulator for repeatable UI and unit tests | Current user experience and App Review-relevant behavior | As of 2026-05-15, the local machine has iOS 26.4 simulators installed. |
| Current simulator | iOS 26.4 or newer installed simulator runtime | iPhone simulator, preferably a small-screen and large-screen profile | CI, keyboard UI, onboarding UI, App Group handoff, insert/context logic in test hosts | Simulator results are useful for automation but not authoritative for microphone-in-keyboard, Open Access, extension memory ceiling, or real app insertion. |
| Intermediate compatibility | iOS 18.x, latest available patch | Physical device or simulator when available | Regression sweep before TestFlight / release | Useful because many active devices may sit between the minimum baseline and current iOS. Not a Phase 0 blocker if unavailable locally. |

Manual-device coverage is **deferred as of 2026-05-15**. Continue with simulator-safe implementation work and non-device evaluations, but do not claim the primary keyboard recording flow is production-viable until at least one physical iPhone pass is completed.

Minimum hardware requirement before Phase 1 sign-off: **one physical iPhone** running either iOS 17.x or current iOS 26.x. If only one physical version is available, record the missing version as a testing gap and close it with TestFlight or a borrowed device before release readiness.

---

## Phase 0 tests (spikes — produce written verdicts)

- Insert test text in: Apple Notes, Mail, Messages, Safari, a known masked field (e.g., credit-card field). Pure context-planning rules are covered by [../spikes/insert-and-context.md](../spikes/insert-and-context.md); host-app insertion validation is still pending.
- Behavior in **Secure Field** and **Phone Pad**.
- Behavior after **Extension cold restart**.
- Behavior **without App Group access** (entitlement misconfigured) — `KeyboardState.noSharedAccess` shown.
- **Apple Speech** in German, English, mixed German / English.
- **In-keyboard recording** on the required iOS test versions above — peak memory + tap-to-record latency under [performance budgets](performance-and-memory.md). Physical device results are required for the verdict; simulator runs are supporting evidence only.
- **App Group concurrency** under contention — interleaved writes from app + extension; verify the generation-counter protocol from [data-and-storage.md](data-and-storage.md). **Done for `PendingInsert`:** [../spikes/app-group-store-contention.md](../spikes/app-group-store-contention.md).
- **`openURL` from extension** with and without Open Access. Harness is documented in [../spikes/open-access-behavior.md](../spikes/open-access-behavior.md); manual matrix is still pending.

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
- Performance budgets met on the minimum supported iOS test tier and the current shipping iOS test tier — see [performance-and-memory.md](performance-and-memory.md).

---

## Phase 4 regression tests

- Marked text / IME composition flow.
- RTL text insertion (no crash, logical order preserved).
- Selection replacement on every supported field type.
- Undo grouping — single undoable transaction per insert.
- Predictive override detection (post-insert context check).
- Masked / formatted fields — clipboard fallback fires.
- Performance budgets re-validated on the **minimum supported iOS** tier and the current shipping iOS tier.

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
- Minimum deployment-target decision: [../spikes/min-ios-investigation.md](../spikes/min-ios-investigation.md)
