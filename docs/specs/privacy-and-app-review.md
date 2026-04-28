# Spec: Privacy & App Review

> **Spec status:** Accepted (v1)
> **Implementation status:** In progress (`RequestsOpenAccess` enabled; narrative drafted later in Phase 0)
> **Last updated:** 2026-04-28
> **Owners:** product + iOS

Permissions, privacy posture, telemetry, and the App Store Review narrative. App-Review-sensitive — read before changing user-facing wording.

---

## Permissions

| Permission | Why | When asked |
| --- | --- | --- |
| Microphone | Recording in the keyboard (primary) and in the app (fallback) | At first dictation; explained in onboarding |
| Speech Recognition | `SFSpeechRecognizer` for raw transcript | At first dictation; explained in onboarding |
| Open Access (Full Access) | Enables in-keyboard recording (primary flow), `openURL` from extension, smoother App Group sync | Recommended in onboarding; the MVP works without it via fallback flow |

### Permission copy

`NSMicrophoneUsageDescription` and `NSSpeechRecognitionUsageDescription` strings are **App-Review-sensitive**. Wording must match the actual behavior described in this spec; reviewers compare them against runtime usage. Do not tweak in passing.

---

## Open Access (Full Access) policy

- **Posture:** optional with fallback. The MVP works without Open Access via the fallback flow — see [architecture.md](architecture.md).
- **Enables:** in-keyboard recording, `openURL` from the keyboard, smoother App Group sync, network access (e.g., remote LLM if ever enabled).
- **Phase 0 must produce** a written go/no-go on whether the microphone path inside the keyboard is reliable enough on the chosen iOS baseline to be the primary flow.

---

## Privacy rules

- **No audio storage** in the MVP except for explicit, opt-in debugging.
- **Raw and final text** remain local unless an external LLM mode is enabled. External LLM is **off by default** and gated on a separate explicit privacy review.
- If external LLM is enabled, the active mode must be visible and disableable from the main UI. Audio is **never** sent to a remote LLM — only post-recognition text.
- The Keyboard Extension reads only the data it needs for insert / favorites.
- Secure Fields are not bypassed.
- **No silent network telemetry.** All diagnostics stay local in the App Group store unless the user opts in to share with support.

---

## Telemetry & crash reporting

- **Crash reporting** is required from Phase 0. Default choice: Apple's **MetricKit** (privacy-friendly, no network). Third-party (Sentry, Firebase Crashlytics) requires an explicit Phase 0 decision and a privacy-policy update.
  - Rationale for MetricKit default: the keyboard extension cannot reliably make network calls without Open Access.
- **Diagnostic events** are stored in a local-only ring buffer in the App Group container and are viewable in Settings → Diagnostics.
- **Extension crash visibility** — the containing app inspects MetricKit reports on launch and surfaces a "Last keyboard error" hint in onboarding / settings.

---

## App Review narrative

Custom keyboards combined with microphone access and (optionally) network-bound LLMs face elevated App Review scrutiny. This narrative is drafted in **Phase 0** and refined throughout. App reviewers will ask each of these questions; the answers must be ready before submission.

- **Why a custom keyboard?** Apple's system dictation does not allow VoiceFlow to format, correct, or apply user vocabulary before insertion. VoiceFlow's value is post-recognition processing — that requires our own surface.
- **Why microphone?** Recording is owned by VoiceFlow; we do not share or upload audio.
- **Why Open Access (when requested)?** To enable in-keyboard recording and avoid forcing users into the fallback flow. The dual-flow design exists specifically so users who decline Open Access still get a working product.
- **What leaves the device?** By default, nothing. If the user enables remote LLM processing (off by default), only post-recognition text is sent; audio is never sent; the active mode is visible in the UI.
- **What happens in Secure Fields?** VoiceFlow defers to the system; we never bypass.

### Privacy nutrition label

Drafted in Phase 0, finalized in Phase 6. Categories:

- **Microphone** — linked to user (used for recording).
- **Audio Data** — not collected (audio is processed in-memory and never persisted by default).
- **User Content (text)** — linked to user, processed locally only unless remote LLM is explicitly enabled.

---

## Cross-references

- The dual-flow design that justifies the Open Access posture: [architecture.md](architecture.md)
- Permission strings and localization: [accessibility-and-localization.md](accessibility-and-localization.md)
- Onboarding copy lives with [architecture.md](architecture.md) → Flow A
