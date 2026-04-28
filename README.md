# VoiceFlow iOS

VoiceFlow iOS is a keyboard-centered dictation and text-formatting app. While the user is working in another iOS app, VoiceFlow records, transcribes, formats, and inserts the final text into the active text field through a custom keyboard extension.

## Architecture in one sentence

A custom keyboard extension owns the user-visible flow. With **Open Access** granted, recording and transcription run **inside the keyboard** (primary flow). Without Open Access, the keyboard hands off to the containing app and the user returns manually (fallback flow).

```text
Primary flow (Open Access granted)
  Keyboard Extension
    -> records audio
    -> SFSpeechRecognizer transcribes
    -> postprocesses (rules + optional LLM)
    -> inserts via UITextDocumentProxy.insertText(...)

Fallback flow (Open Access denied)
  Keyboard Extension
    -> deep-links to containing app
  Containing app
    -> records, transcribes, postprocesses
    -> writes PendingInsert into the App Group store
  User returns to the target app manually
  Keyboard Extension reads PendingInsert and inserts
```

The containing app additionally owns onboarding, permissions, history, vocabulary, and settings.

## Repository state

- **Roadmap (index + phase status):** [`ROADMAP.md`](ROADMAP.md)
- **Specifications (canonical detail):** [`docs/specs/`](docs/specs/) — one file per topic
- **Agent guide (shared across all AI agents):** [`AGENTS.md`](AGENTS.md)
- **Claude-specific notes:** [`CLAUDE.md`](CLAUDE.md) — thin pointer to `AGENTS.md`
- **Xcode project:** scaffolded under [`VoiceFlow/`](VoiceFlow) with four targets (`VoiceFlow`, `VoiceFlowKeyboard`, `VoiceFlowTests`, `VoiceFlowUITests`). Sources are stubs. **App Group entitlements, `RequestsOpenAccess`, and the shared model package are wired; shared store is still pending** — these are Phase 0 prerequisites described in [`ROADMAP.md`](ROADMAP.md).

## Key product constraints

VoiceFlow does not replace Apple's system dictation button and cannot intercept Apple dictation output. The microphone glyph below the iOS keyboard belongs to Apple. VoiceFlow shows its own microphone button **inside** the VoiceFlow keyboard UI.

VoiceFlow is unavailable in Secure Fields, Phone Pads, and apps that disable third-party keyboards. The MVP must handle these cases with a clear fallback (clipboard copy + brief explanation), never with private APIs.

## Shared identifiers

| Identifier | Value |
| --- | --- |
| App Group | `group.com.voiceflow.shared` |
| Containing app bundle ID | `me.tissanr.VoiceFlow` |
| Keyboard extension bundle ID | `me.tissanr.VoiceFlow.VoiceFlowKeyboard` |
| Minimum iOS | `17.0` |

## Where to start

1. Skim [`ROADMAP.md`](ROADMAP.md) for the spec index and current phase status.
2. Open the relevant spec under [`docs/specs/`](docs/specs/) for the topic you're working on.
3. Read [`AGENTS.md`](AGENTS.md) before making any code changes — it is the shared contract for AI agents working in this repo.
4. Phase 0 (foundation, spikes, privacy narrative) gates Phase 1. Do not skip it.
