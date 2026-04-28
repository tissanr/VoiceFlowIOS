# Spec: Architecture

> **Spec status:** Accepted (v1)
> **Implementation status:** In progress (shared model package wired; app and keyboard implementations pending)
> **Last updated:** 2026-04-28
> **Owners:** product + iOS

---

## iOS Assumptions

### What iOS allows

- A Custom Keyboard Extension can be enabled systemwide as a keyboard.
- When VoiceFlow is the active keyboard, it can insert text into the currently selected text field using `UITextDocumentProxy.insertText(...)`.
- The Keyboard Extension can read limited cursor context: `documentContextBeforeInput`, `documentContextAfterInput`.
- The containing app and Keyboard Extension can exchange data through App Groups.
- With **Open Access** ("Allow Full Access") enabled, the Keyboard Extension may use network APIs, `openURL` from the extension, and richer App Group access. Microphone access from a Keyboard Extension is also conditional on Open Access.

### What iOS does not allow

- No global push-to-talk hotkey.
- No systemwide simulation of keyboard input into arbitrary apps.
- No registration as a replacement provider for Apple's system dictation.
- No interception of normal Apple dictation output.
- No availability in every field: Secure Fields, Phone Pads, and apps that disable third-party keyboards can exclude VoiceFlow.
- **No programmatic "Return to App"** — iOS forbids forcing the user back to the previous app. The user must use the iOS breadcrumb or App Switcher.

### What must be validated in Phase 0

- Microphone + `SFSpeechRecognizer` running **inside** a Keyboard Extension on the chosen iOS baseline (with Open Access). The folklore says it's unreliable; we are explicitly challenging that.
- `openURL` from the Keyboard Extension (typically requires Open Access).

---

## Dual-flow architecture

### Primary flow (Open Access granted)

```text
User focuses a text field in the target app
  -> User switches to VoiceFlow Keyboard
  -> User taps microphone button in the keyboard
  -> Keyboard Extension starts AVAudioEngine + SFSpeechRecognizer
  -> User stops recording
  -> Keyboard transcribes and applies postprocessing
  -> Keyboard previews the result inline
  -> User taps Insert
  -> UITextDocumentProxy.insertText(...)
```

No app switch. No Return Trip.

### Fallback flow (Open Access denied, or in-keyboard recording infeasible)

```text
User taps microphone button in the keyboard
  -> Keyboard shows: "Open Full Access for in-keyboard recording, or tap to record in the VoiceFlow app"
  -> Keyboard deep-links to (or instructs the user to open) the containing app
  -> Containing app records, transcribes, postprocesses
  -> Containing app writes PendingInsert to the App Group store
  -> Containing app shows: "Switch back to <target app> to insert"
  -> User returns manually (breadcrumb or App Switcher)
  -> Keyboard Extension reads PendingInsert and offers Insert
```

Fallback flow is degraded UX. Users are told why and how to upgrade (enable Open Access).

### Why dual-flow

- **Honesty:** the Return Trip is fragile; admitting it as a fallback is more honest than making it the default.
- **App Review:** Open Access becomes an *optional improvement*, not a hard requirement.
- **Privacy posture:** users who decline Open Access still get a working product.

---

## Microphone button position

The microphone glyph below the iOS keyboard belongs to Apple's system dictation. VoiceFlow cannot register itself there as an alternative provider.

`UIInputViewController.hasDictationKey` does **not** mean VoiceFlow can replace Apple's dictation button. It only controls whether a Custom Keyboard Extension presents its own dictation key inside its **own UI**, so iOS does not also show a confusing system dictation button while VoiceFlow is active.

Consequence: VoiceFlow shows its own microphone button **inside the VoiceFlow keyboard UI**. Tapping it starts the dictation flow (primary or fallback depending on Open Access).

---

## MVP scope

### Must Have

- Keyboard Extension can insert text into supported text fields.
- Containing app can request microphone and speech-recognition permissions.
- **Primary flow** works end-to-end on the chosen iOS baseline with Open Access enabled.
- **Fallback flow** works end-to-end without Open Access.
- Rule-based postprocessing on the result.
- App Group store with the documented concurrency protocol — see [Data & Storage spec](data-and-storage.md).
- Secure Field / Phone Pad / disabled-keyboard detection with clipboard fallback.
- Error states are shown visibly and never silently dropped.
- Onboarding screen explaining: keyboard activation, microphone permission, speech-recognition permission, Open Access trade-off.
- Numeric performance budgets met — see [Performance & Memory spec](performance-and-memory.md).
- Accessibility baseline — see [Accessibility & Localization spec](accessibility-and-localization.md).

### Should Have

- Simple history list (last 20) in the containing app.
- Manual editing of the final text before saving.
- Context-aware capitalization using `documentContextBeforeInput`.
- Language setting for German / English / Auto (subject to Apple Speech availability).

### Not In MVP

- Custom Whisper / Core ML ASR.
- Fully local LLM.
- Automatic insert without user confirmation.
- Advanced analytics.
- iCloud sync.
- A full custom keyboard with all standard keys.
- Remote (network-bound) LLM — gated on a separate explicit decision and privacy review.

---

## User flows

### Flow A — First Setup

```text
User opens VoiceFlow app
  -> App explains keyboard setup, microphone, speech recognition, Open Access trade-off
  -> User enables VoiceFlow Keyboard in iOS Settings
  -> User chooses Open Access (recommended) or skips (fallback flow)
  -> User grants microphone permission
  -> User grants speech-recognition permission
  -> App runs a test dictation
  -> App shows: "Keyboard ready (in-keyboard mode)" or "Keyboard ready (handoff mode)"
```

**Acceptance:** user understands, in plain language, what each permission and Open Access changes.

### Flow B (primary) — In-keyboard dictation

```text
User focuses a text field in target app
  -> Switches to VoiceFlow Keyboard
  -> Taps microphone button
  -> Keyboard records, transcribes, postprocesses
  -> Keyboard previews result inline
  -> User taps Insert
  -> Text inserted via UITextDocumentProxy.insertText(...)
```

**Acceptance:** completes without leaving the target app.

### Flow C (fallback) — Handoff dictation

```text
User taps microphone (Open Access disabled)
  -> Keyboard explains: "Recording happens in the VoiceFlow app. Tap to continue."
  -> Containing app opens, records, transcribes, postprocesses
  -> Containing app writes PendingInsert (generation N+1)
  -> User returns to target app via breadcrumb / App Switcher
  -> Keyboard reads PendingInsert and offers Insert
```

**Acceptance:** no recognized text is lost across app switches; PendingInsert TTL handled cleanly.

### Flow D — Reinsert latest dictation

```text
User opens VoiceFlow Keyboard
  -> Keyboard shows latest dictation (from App Group store)
  -> User taps Insert
```

**Acceptance:** works without a new recording.

### Flow E — Unsupported field

```text
User is in Secure Field / Phone Pad / app without third-party keyboards
  -> VoiceFlow detects pre-record
  -> Keyboard or app explains the limitation
  -> Final text placed on clipboard as fallback
```

**Acceptance:** never silently fail; never bypass iOS limits.

---

## Target architecture (modules)

```text
VoiceFlowApp (containing app)
  -> RecordingController             (used in fallback flow only)
       AVAudioSession / AVAudioEngine
  -> SpeechEngine                    (AppleSpeechEngine first; protocol allows swap)
  -> PostProcessor                   (rules + optional LLM)
  -> VocabularyStore
  -> DictationStore                  (full history, status)
  -> SettingsStore
  -> OnboardingFlow

VoiceFlowKeyboardExtension
  -> KeyboardViewController          (mic, Insert, Retry, Cancel, Next-Keyboard globe)
  -> RecordingController             (primary flow only, gated on Open Access)
  -> SpeechEngine
  -> PostProcessor
  -> TextProxyWriter                 (UITextDocumentProxy.insertText(...))
  -> CursorContextReader             (documentContextBeforeInput / AfterInput)
  -> SharedStoreClient               (generation-counter aware)
  -> InsertGuard                     (Secure Field / Phone Pad / disabled-keyboard detection)

Shared (extension-safe Swift package or framework)
  -> Models (DictationRecord, PendingInsert, VocabularyEntry, VoiceFlowSettings)
  -> SharedStoreClient (read paths usable from both targets)
  -> PostProcessor rule pipeline
  -> SpeechEngine protocol
```

Code that uses APIs **unavailable to extensions** stays exclusively in the containing app. The shared framework must compile against the extension-safe API subset.

Current shared package path: [../../VoiceFlow/VoiceFlowShared](../../VoiceFlow/VoiceFlowShared).

---

## Core technologies

| Area | Technology |
| --- | --- |
| App UI | SwiftUI |
| Keyboard Extension UI | `UIInputViewController`, UIKit (SwiftUI hosted where stable) |
| Text insertion | `UITextDocumentProxy.insertText(...)` |
| Cursor context | `documentContextBeforeInput`, `documentContextAfterInput` |
| Audio recording | `AVAudioSession`, `AVAudioEngine` |
| Speech recognition (MVP) | `SFSpeechRecognizer` + `supportsOnDeviceRecognition` |
| Postprocessing | Rule pipeline + optional local LLM adapter |
| Persistence | SwiftData in the App Group container for history and vocabulary |
| Extension comms | App Groups + UserDefaults + SwiftData |
| Shortcuts | App Intents |
| Later offline ASR | Whisper / Core ML or whisper.cpp / Metal |

---

## Cross-references

- Data structures and concurrency: [data-and-storage.md](data-and-storage.md)
- Keyboard UI states and insert details: [keyboard-and-insert.md](keyboard-and-insert.md)
- Speech and postprocessing details: [speech-and-postprocessing.md](speech-and-postprocessing.md)
- Performance and memory budgets: [performance-and-memory.md](performance-and-memory.md)
