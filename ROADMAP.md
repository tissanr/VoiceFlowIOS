# VoiceFlow iOS — Roadmap

> **Last updated:** 2026-05-05
> **Purpose:** Index of specifications, implementation status, and phase plan. The detailed product spec lives in [`docs/specs/`](docs/specs/) — start there for any deep dive.

---

## Implementation Status

Start here to see where the project is. The table is intentionally split by subphase so the active work is visible without reading the whole roadmap.

**Status legend:** 🟥 Not started · 🟧 In progress · 🟨 Awaiting review / blocked · 🟩 Done · ⬛ Superseded

| Phase | Subphase | Status | Current state / next gate |
| --- | --- | --- | --- |
| Phase 0 — Foundation, Spikes, Privacy Narrative | 0.1 Docs and decision alignment | 🟩 Done | Subphase tracker added; architecture implementation status now matches the spec. Keep specs and roadmap in sync as future decisions land. |
| Phase 0 — Foundation, Spikes, Privacy Narrative | 0.2 App Group + Open Access scaffold | 🟩 Done | App and keyboard entitlements are wired; keyboard `RequestsOpenAccess = true`. |
| Phase 0 — Foundation, Spikes, Privacy Narrative | 0.3 Minimum iOS baseline | 🟩 Done | iOS 17.0 selected in [`docs/spikes/min-ios-investigation.md`](docs/spikes/min-ios-investigation.md) and applied to the project. |
| Phase 0 — Foundation, Spikes, Privacy Narrative | 0.4 Shared package + `PendingInsert` store | 🟩 Done | `VoiceFlowShared` model package and generation-counter `SharedStoreClient` exist; App Group contention spike passed. |
| Phase 0 — Foundation, Spikes, Privacy Narrative | 0.5 In-keyboard recording spike | 🟧 In progress | Harness exists; real-device memory, latency, and stability verdict still pending. |
| Phase 0 — Foundation, Spikes, Privacy Narrative | 0.6 Remaining platform spikes | 🟥 Not started | Open Access behavior, insert, context, audio interruption, speech locale, and crash-reporting verdicts still pending. |
| Phase 0 — Foundation, Spikes, Privacy Narrative | 0.7 Privacy / App Review / onboarding drafts | 🟥 Not started | Privacy nutrition label, App Review narrative, and onboarding copy still pending. |
| Phase 1 — Keyboard MVP with Secure-Field handling | 1.1 Keyboard UI state shell | 🟥 Not started | Build Compact, Recording, Transcribing, Reviewing, Pending, and InsertUnavailable states after Phase 0 sign-off. |
| Phase 1 — Keyboard MVP with Secure-Field handling | 1.2 Primary in-keyboard dictation flow | 🟥 Not started | Requires Phase 0 in-keyboard recording verdict. |
| Phase 1 — Keyboard MVP with Secure-Field handling | 1.3 Fallback containing-app handoff flow | 🟥 Not started | Requires Phase 0 handoff and App Group assumptions to stay valid. |
| Phase 1 — Keyboard MVP with Secure-Field handling | 1.4 Manual insert + unsupported-field fallback | 🟥 Not started | Covers `UITextDocumentProxy.insertText(...)`, Secure Fields, Phone Pads, disabled keyboards, and clipboard fallback. |
| Phase 1 — Keyboard MVP with Secure-Field handling | 1.5 MVP onboarding, accessibility, and diagnostics baseline | 🟥 Not started | Covers activation flow, Open Access trade-off, VoiceOver labels, Dynamic Type baseline, and MetricKit surfacing. |
| Phase 2 — Postprocessing, Vocabulary, Accessibility hardening | 2.1 `PostProcessor` rule pipeline | 🟥 Not started | Correction levels and deterministic local rules. |
| Phase 2 — Postprocessing, Vocabulary, Accessibility hardening | 2.2 Vocabulary learning + management UI | 🟥 Not started | Learn from raw vs. corrected text; show, edit, delete, and disable vocabulary entries. |
| Phase 2 — Postprocessing, Vocabulary, Accessibility hardening | 2.3 LLM adapter interface + guardrails | 🟥 Not started | Exchangeable interface only; remote LLM remains gated by explicit privacy review. |
| Phase 2 — Postprocessing, Vocabulary, Accessibility hardening | 2.4 Accessibility and localization hardening | 🟥 Not started | VoiceOver primary flow, German + English strings, Dynamic Type, contrast, and mixed-language handling. |
| Phase 3 — History, Analytics, Reuse | 3.1 History search and reuse | 🟥 Not started | Full history, search, and reuse from the containing app. |
| Phase 3 — History, Analytics, Reuse | 3.2 Keyboard latest / favorites / snippets | 🟥 Not started | Memory-budget-aware access to recent and saved text from the keyboard. |
| Phase 3 — History, Analytics, Reuse | 3.3 Local analytics + App Shortcuts | 🟥 Not started | Words, WPM, streaks, latest dictation shortcuts, copy latest, and share latest. |
| Phase 4 — Robustness, Edge Cases, Performance Budgets | 4.1 Insert edge-case hardening | 🟥 Not started | Marked text, RTL, undo grouping, masked fields, predictive overrides, spacing, and selection behavior. |
| Phase 4 — Robustness, Edge Cases, Performance Budgets | 4.2 App Group sync hardening | 🟥 Not started | Low-memory behavior, fast app switching, and poor-condition sync validation. |
| Phase 4 — Robustness, Edge Cases, Performance Budgets | 4.3 Lowest-device performance validation | 🟥 Not started | Re-measure all numeric budgets on the lowest-supported device class. |
| Phase 4 — Robustness, Edge Cases, Performance Budgets | 4.4 Layout and RTL hardening | 🟥 Not started | Landscape, small displays, RTL layout safety, and logical-order insertion. |
| Phase 5 — Optional Offline ASR | 5.1 Offline ASR evaluation | 🟥 Not started | Only starts if Apple Speech is proven insufficient for a defined user segment. |
| Phase 5 — Optional Offline ASR | 5.2 Fully local mode decision | 🟥 Not started | Decide whether Whisper / Core ML meaningfully improves privacy, quality, or reliability. |
| Phase 6 — Release Readiness | 6.1 Release privacy package | 🟥 Not started | Final permission copy, privacy text, nutrition label, and App Review narrative. |
| Phase 6 — Release Readiness | 6.2 Data deletion, export, and backup | 🟥 Not started | User-facing controls for history and vocabulary lifecycle. |
| Phase 6 — Release Readiness | 6.3 Release pipeline and submission readiness | 🟥 Not started | fastlane, TestFlight, App Store Connect, active engine display, and final review pass. |

---

## Product Goal

VoiceFlow iOS lets users dictate text while working in other iOS apps, improves the recognized raw transcript, and inserts the final text into the currently selected text field. The architecture is **dual-flow**: in-keyboard recording when Open Access is granted, fallback to a containing-app handoff otherwise. Both flows insert via `UITextDocumentProxy.insertText(...)`.

VoiceFlow does not replace Apple's system dictation. It runs as a custom keyboard.

---

## Specifications

| Spec | Owns | Spec status | Implementation |
| --- | --- | --- | --- |
| [architecture](docs/specs/architecture.md) | iOS assumptions, dual-flow design, MVP scope, user flows, target architecture, core technologies | Accepted (v1) | 🟧 In progress (shared model package wired; app and keyboard implementations pending) |
| [data-and-storage](docs/specs/data-and-storage.md) | App Group identifiers, storage layout, state and data models, shared-store concurrency protocol | Accepted (v2) | 🟧 In progress (`PendingInsert` shared-store handoff verified under contention; SwiftData history/vocabulary store pending) |
| [speech-and-postprocessing](docs/specs/speech-and-postprocessing.md) | Audio session, `SpeechEngine`, postprocessing pipeline, vocabulary, guardrails | Accepted (v1) | 🟥 Not started |
| [keyboard-and-insert](docs/specs/keyboard-and-insert.md) | Keyboard UI states, insert path, edge cases (marked text, RTL, masked fields, undo grouping), `InsertGuard` | Accepted (v1) | 🟥 Not started |
| [performance-and-memory](docs/specs/performance-and-memory.md) | Numeric memory / latency / energy budgets and validation procedure | Accepted (v1) | 🟥 Not started (budgets unverified) |
| [accessibility-and-localization](docs/specs/accessibility-and-localization.md) | VoiceOver, Dynamic Type, contrast, RTL safety, `Localizable.xcstrings`, mixed-language dictation | Accepted (v1) | 🟥 Not started |
| [privacy-and-app-review](docs/specs/privacy-and-app-review.md) | Permissions, Open Access policy, telemetry, App Review narrative, privacy nutrition label | Accepted (v1) | 🟧 In progress (`RequestsOpenAccess` enabled; narrative pending) |
| [build-and-ci](docs/specs/build-and-ci.md) | Local build commands, CI pipeline, code signing, fastlane | Accepted (v1) | 🟥 Not started (manual local builds work) |
| [testing](docs/specs/testing.md) | Phase 0 spike tests, MVP acceptance tests, Phase 4 regression matrix | Accepted (v1) | 🟧 In progress (`VoiceFlowShared` tests and App Group contention spike harness exist) |

**Status legend:** 🟥 Not started · 🟧 In progress · 🟨 Awaiting review · 🟩 Done · ⬛ Superseded

If a spec changes meaningfully, bump its version in the spec header and update this table.

---

## Phase plan (summary)

Each phase below lists exit criteria. The deep details live in the linked specs, and the current subphase status lives in the implementation table at the top.

### Phase 0 — Foundation, Spikes, Privacy Narrative

**Status:** 🟧 In progress

Scaffold hardening (immediate, low-risk):

- Add `.entitlements` files for both targets with `com.apple.security.application-groups = ["group.me.tissanr.VoiceFlow.shared"]` — see [data-and-storage](docs/specs/data-and-storage.md). **Done:** `VoiceFlow/VoiceFlow/VoiceFlow.entitlements` and `VoiceFlow/VoiceFlowKeyboard/VoiceFlowKeyboard.entitlements` are wired into target signing settings.
- Set `RequestsOpenAccess = true` in [`VoiceFlow/VoiceFlowKeyboard/Info.plist`](VoiceFlow/VoiceFlowKeyboard/Info.plist) (so users *can* grant it; the app still works without). **Done.**
- Set the project deployment target to the chosen baseline after the min-iOS investigation. **Done:** [`docs/spikes/min-ios-investigation.md`](docs/spikes/min-ios-investigation.md) selected iOS 17.0 and the project now uses `IPHONEOS_DEPLOYMENT_TARGET = 17.0`.

Spikes (each must produce a written verdict):

- **In-keyboard recording** — microphone + `SFSpeechRecognizer` inside the Keyboard Extension on the chosen iOS baseline; measure peak memory, latency, stability over 5 min of repeated 10 s dictations. Harness implemented; real-device verdict pending. See [`docs/spikes/in-keyboard-recording.md`](docs/spikes/in-keyboard-recording.md). (See [performance-and-memory](docs/specs/performance-and-memory.md), [speech-and-postprocessing](docs/specs/speech-and-postprocessing.md).)
- **Open Access** — confirm `openURL` and microphone-in-extension behavior with and without Open Access. Verdict: feature matrix. (See [privacy-and-app-review](docs/specs/privacy-and-app-review.md).)
- **App Group store** — `SharedStoreClient` with the generation-counter protocol is implemented for `PendingInsert`; cross-process contention spike passed with file-lock + synchronized suite access. **Done. Verdict:** viable for Phase 1 if all app/extension code uses `SharedStoreClient`; direct raw key access is prohibited. See [`docs/spikes/app-group-store-contention.md`](docs/spikes/app-group-store-contention.md).
- **Insert** — insert in Notes, Mail, Messages, Safari, plus a known masked field. (See [keyboard-and-insert](docs/specs/keyboard-and-insert.md).)
- **Context** — read context before / after cursor; verify auto-capitalization and spacing logic.
- **Audio** — interruption tests (call, Siri, Focus, headphone unplug) for both flows.
- **Speech** — Apple Speech in German, English, and mixed; on-device availability per locale.
- **Min-iOS investigation** — one-page comparison of iOS 17 / 18 / 26 covering Speech APIs, on-device support, SwiftData stability, audio session APIs, Keyboard Extension capabilities. Pick the lowest version with a meaningful simplicity win. **Done:** iOS 17.0 selected; see [`docs/spikes/min-ios-investigation.md`](docs/spikes/min-ios-investigation.md).
- **Crash reporting** — decide MetricKit vs. third-party. (See [privacy-and-app-review](docs/specs/privacy-and-app-review.md).)

Drafts:

- Privacy nutrition label.
- App Review narrative.
- Onboarding copy (Flow A wording, Open Access trade-off).

**Exit criteria:** primary-flow viability decided with evidence; Open Access posture re-confirmed (default: optional with fallback); min-iOS decided; entitlements wired and verified end-to-end; privacy narrative + onboarding copy written; all former Open Decisions verified against spike results (see Resolved Decisions below).

---

### Phase 1 — Keyboard MVP with Secure-Field handling

**Status:** 🟥 Not started

- Keyboard UI states (Compact, Recording / Transcribing / Reviewing, Pending, InsertUnavailable). See [keyboard-and-insert](docs/specs/keyboard-and-insert.md).
- Primary flow end-to-end (Open Access enabled).
- Fallback flow end-to-end (no Open Access). Includes "Switch back to <target app>" copy after writing `PendingInsert`.
- `SharedStoreClient` honors the generation-counter protocol. See [data-and-storage](docs/specs/data-and-storage.md).
- Rule-based postprocessing in the shared framework. See [speech-and-postprocessing](docs/specs/speech-and-postprocessing.md).
- Manual insert through Keyboard Extension.
- **Secure Field / Phone Pad / disabled-keyboard detection with clipboard fallback** (pulled forward from old Phase 4).
- All [performance budgets](docs/specs/performance-and-memory.md) met on a representative device (iPhone 12 or newer).
- Onboarding screen with keyboard activation, permissions, Open Access trade-off.
- Accessibility baseline (VoiceOver labels, 44×44 hit targets, Dynamic Type to XXXL).
- Telemetry: MetricKit reports surfaced in Settings.

**Exit criterion:** a user, in another app, can switch to VoiceFlow Keyboard, dictate, format, and insert text into the focused field — on **both** flows — and gets a clean fallback in unsupported fields.

---

### Phase 2 — Postprocessing, Vocabulary, Accessibility hardening

**Status:** 🟥 Not started

- `PostProcessor` with correction levels (minimal / soft / medium).
- LLM adapter as an exchangeable service; default local-only / off for MVP.
- Hallucination guardrails (word-count deviation, similarity ratio, repetition filter).
- Vocabulary learning from raw vs. corrected text.
- Vocabulary UI (show, edit, delete, disable).
- Accuracy ratio stored per dictation.
- VoiceOver completes primary flow without sighted assistance.
- German + English UI strings finalized (see [accessibility-and-localization](docs/specs/accessibility-and-localization.md)).

**Exit criterion:** domain terms reliably corrected; LLM never freely adds content or rewrites meaning; VoiceOver flow passes.

---

### Phase 3 — History, Analytics, Reuse

**Status:** 🟥 Not started

- History with search.
- Insert latest dictation directly from keyboard.
- Favorites / snippets in keyboard (memory-budget aware).
- Local analytics: words today, words 7d, total words, WPM, streak, longest text, average session.
- App Shortcuts: start new dictation, copy latest, share latest.
- Localization completeness audit.

**Exit criterion:** user finds old dictations, re-inserts them, understands their usage history.

---

### Phase 4 — Robustness, Edge Cases, Performance Budgets

**Status:** 🟥 Not started

- Full insert-edge-case list addressed (marked text, RTL, undo grouping, masked fields, predictive overrides). See [keyboard-and-insert](docs/specs/keyboard-and-insert.md).
- Improve insert context (leading space, sentence start, paragraph start, selection replacement where allowed).
- Harden App Group sync under poor conditions (low memory, fast app switching).
- Re-measure all [performance budgets](docs/specs/performance-and-memory.md) on the **lowest-supported** device class. Fix or document deviations.
- Landscape and small-display layouts.
- RTL hardening (no crashes, correct logical-order insertion).

**Exit criterion:** no silent failures in iOS edge cases; all numeric budgets met on minimum-supported hardware.

---

### Phase 5 — Optional Offline ASR (gated by proven need)

**Status:** 🟥 Not started

- Evaluate Whisper / Core ML or whisper.cpp / Metal.
- Test tiny / base / small model sizes.
- Evaluate batch vs. streaming.
- Measure battery, memory, thermal load, latency.
- Compare quality against Apple Speech.
- Define "fully local" privacy mode.

**Exit criterion:** custom ASR ships only if it provides a clear, measured advantage over Apple Speech for a defined user segment.

---

### Phase 6 — Release Readiness

**Status:** 🟥 Not started

- Active engine display (Apple Speech / Apple On-Device / local Whisper / LLM mode).
- Permission copy finalized for microphone and Speech Recognition (App-Review-sensitive — see [privacy-and-app-review](docs/specs/privacy-and-app-review.md)).
- Data deletion for history and vocabulary.
- Export / backup for history and vocabulary.
- Privacy text for Keyboard Extension and Open Access finalized.
- Privacy nutrition label finalized.
- App Review narrative finalized.
- fastlane release pipeline (see [build-and-ci](docs/specs/build-and-ci.md)).

**Exit criterion:** stable permission and privacy story; user understands which data is processed where.

---

## Recommended sequence

1. **Phase 0** — Foundation, spikes, privacy narrative.
2. **Phase 1** — Keyboard MVP (both flows) + Secure-Field handling.
3. **Phase 2** — Postprocessing, vocabulary, accessibility hardening.
4. **Phase 3** — History, analytics, reuse.
5. **Phase 4** — Robustness, edge cases, perf budgets validated on min-spec hardware.
6. **Phase 5** — Offline ASR (only with proven need).
7. **Phase 6** — Release readiness.

---

## Resolved Decisions

| Question | Resolution | Where decided |
| --- | --- | --- |
| How does the user return to the target app after recording? | Primary flow eliminates the return trip; fallback uses iOS breadcrumb / App Switcher with explicit "Switch back to <app>" copy. | [architecture](docs/specs/architecture.md) → Dual-flow architecture |
| Auto-insert vs. manual Insert in MVP? | Manual Insert in MVP. Auto-insert post-MVP. | [architecture](docs/specs/architecture.md) → MVP scope |
| Does the Keyboard Extension need `RequestsOpenAccess`? | `RequestsOpenAccess = true` so users *can* grant it. MVP works without via fallback flow. | [privacy-and-app-review](docs/specs/privacy-and-app-review.md) → Open Access policy |
| Which App Group store is most robust? | Locked, synchronized suite preferences for `PendingInsert` and small state; SwiftData in the App Group container for history and vocabulary. Generation-counter protocol mandatory. | [data-and-storage](docs/specs/data-and-storage.md), [min-iOS investigation](docs/spikes/min-ios-investigation.md), [App Group store spike](docs/spikes/app-group-store-contention.md) |
| MVP LLM: local, remote, or interface only? | Interface + local rules in MVP. Remote LLM gated on a separate explicit privacy review. | [privacy-and-app-review](docs/specs/privacy-and-app-review.md) |
| Minimum iOS version? | iOS 17.0. | [min-iOS investigation](docs/spikes/min-ios-investigation.md) |
| Launch languages? | German + English; mixed German / English dictation supported. | [accessibility-and-localization](docs/specs/accessibility-and-localization.md) |
| Audio temporarily storable for debugging? | Off by default; opt-in only. | [privacy-and-app-review](docs/specs/privacy-and-app-review.md) |
| Keyboard-extension history size? | Last 5 entries loaded eagerly; full history only via the containing app. | [performance-and-memory](docs/specs/performance-and-memory.md) |
| VoiceFlow-only keyboard or full keyboard? | MVP: VoiceFlow functions + Next-Keyboard globe. Full character keyboard post-MVP. | [architecture](docs/specs/architecture.md) → MVP scope |

---

## Known Risks

| Risk | Cause | Mitigation |
| --- | --- | --- |
| In-keyboard recording exceeds extension memory budget | Live audio + recognition + UI in 48 MB | Phase 0 spike measures; primary flow restricted to capable device classes; fallback flow ships first-class |
| User declines Open Access | Privacy concern, friction | Fallback flow ships first-class; onboarding explains trade-off in plain language |
| Apple rejects custom-keyboard + microphone combo | Elevated App Review scrutiny | App Review narrative drafted in Phase 0; clear disclosures |
| User loses context while switching apps (fallback flow) | iOS forbids return-to-app | `PendingInsert` with TTL; primary flow used when possible |
| Keyboard unavailable in some apps | App blocks third-party keyboards | Clipboard fallback + clear UI |
| No insert in Secure Fields | iOS replaces custom keyboard with system keyboard | Detected pre-record in Phase 1; communicate clearly |
| Apple Speech unavailable offline | Locale / device / iOS dependency | Per-locale availability check at runtime; allow online mode or evaluate Whisper later |
| LLM hallucinates formatting | Generative model | Guardrails + fallback to raw text; LLM disabled by default |
| App Group race conditions | Cross-process suite sync | `SharedStoreClient` file lock + generation-counter protocol with `consumedGen` tombstone |
