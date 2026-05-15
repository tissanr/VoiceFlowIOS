# Phase 0 Draft: Privacy, App Review, and Onboarding

> **Status:** Drafted; human review required.
> **Date:** 2026-05-15
> **Scope:** Privacy nutrition label draft, App Review narrative draft, and onboarding copy direction for Flow A.

This is a product / App Review draft, not final shipping copy. Do not paste these strings into production UI or App Store Connect without human review.

## Privacy Nutrition Label Draft

Default MVP posture:

| Category | Draft answer | Rationale |
| --- | --- | --- |
| Audio Data | Not collected | Audio is processed in memory for recognition and is not persisted by default. |
| User Content: text | Collected, linked to user, not used for tracking | Dictation history, pending inserts, vocabulary entries, and corrected text are stored locally for app functionality. |
| Diagnostics | Collected, not used for tracking | MetricKit diagnostics and local breadcrumbs are used to diagnose crashes and reliability issues. |
| Identifiers | Not collected for tracking | No advertising identifier or cross-app tracking identifier in MVP. |
| Usage Data | Not collected by default | Local analytics may be stored on device later; no silent network telemetry. |

Processing and sharing notes:

- Audio is never sent to a remote LLM.
- External LLM processing is off by default and remains gated by a separate privacy review.
- Diagnostics are not silently uploaded.
- User-exported diagnostics or support bundles require explicit user action.

## App Review Narrative Draft

VoiceFlow is a custom keyboard for dictation workflows that Apple's system dictation cannot cover. Apple's dictation inserts recognized text directly into the host app; it does not let VoiceFlow apply user vocabulary, formatting rules, review UI, or correction guardrails before insertion. A custom keyboard is required so the user can start a VoiceFlow-owned dictation session and insert the processed result through `UITextDocumentProxy.insertText(...)`.

Microphone access is used only to record the user's own dictation. In the MVP, audio is streamed to Apple's Speech framework for recognition and is not stored by default. The app stores text results, pending inserts, user vocabulary, settings, and local diagnostics in the app / App Group storage needed for the keyboard and containing app to work together.

Full Access is recommended but not mandatory. With Full Access enabled, VoiceFlow can attempt in-keyboard recording and avoid forcing the user to leave the host app. If the user declines Full Access, the fallback flow records in the containing app, writes the result to the App Group store, and asks the user to return manually to insert the text. This fallback exists so Full Access is an optional improvement rather than a hard requirement.

VoiceFlow does not bypass Secure Fields, Phone Pads, or apps that disable third-party keyboards. In unsupported fields, the app explains the iOS limitation and uses clipboard fallback only where appropriate.

By default, no user dictation content is sent to VoiceFlow servers or third-party model providers. If a future remote LLM mode is added, it must be off by default, visibly labeled, disableable, and covered by a separate privacy review. Audio is never sent to a remote LLM.

## Onboarding Copy Direction

Flow A should be short, concrete, and permission-specific.

### Screen 1: What VoiceFlow Adds

Purpose:

- Explain that VoiceFlow is a separate keyboard for dictation and formatting.
- Avoid implying it replaces Apple's system dictation button.

Draft copy:

```text
VoiceFlow adds a dictation keyboard for text you want to review, format, and insert.
It does not replace Apple's dictation button.
```

### Screen 2: Keyboard Setup

Purpose:

- Explain that the user must enable the keyboard in iOS Settings.
- Mention unsupported fields upfront.

Draft copy:

```text
Enable the VoiceFlow keyboard in Settings to use it in other apps.
Some secure fields and apps do not allow third-party keyboards.
```

### Screen 3: Full Access Choice

Purpose:

- Explain the trade-off honestly.
- Make clear the app works without Full Access.

Draft copy:

```text
Allow Full Access for in-keyboard recording.
Without it, recording happens in the VoiceFlow app and you switch back to insert.
```

### Screen 4: Microphone and Speech Recognition

Purpose:

- Explain why both permissions are needed.
- Avoid broad or vague permission language.

Draft copy:

```text
Microphone lets VoiceFlow record your dictation.
Speech Recognition turns that recording into text using Apple's Speech framework.
```

### Screen 5: Ready State

Purpose:

- Confirm the selected mode.
- Set expectations for primary vs. fallback.

Draft copy:

```text
Keyboard ready: in-keyboard mode.
```

Fallback variant:

```text
Keyboard ready: handoff mode.
Record in VoiceFlow, then switch back to insert.
```

## Permission String Direction

These are not final strings. Keep the final strings short and aligned with runtime behavior.

```text
NSMicrophoneUsageDescription:
VoiceFlow uses the microphone to record dictation you start.

NSSpeechRecognitionUsageDescription:
VoiceFlow uses Apple's Speech Recognition to turn your dictation into text.
```

## Human Review Checklist

- Confirm App Store Connect privacy nutrition answers against the final implemented data paths.
- Confirm permission strings match the exact runtime behavior in both primary and fallback flows.
- Confirm Open Access wording does not imply hidden network use.
- Confirm onboarding does not promise support in Secure Fields, Phone Pads, or apps that disable third-party keyboards.
- Confirm any future LLM mode gets a separate privacy review before implementation.
