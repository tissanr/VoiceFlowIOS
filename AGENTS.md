# Codex Instructions

## Project

VoiceFlow iOS is an iOS product specification and future native app for a keyboard-centered dictation workflow.

The intended architecture is:

- `VoiceFlowApp`: containing app for onboarding, permissions, recording, speech recognition, postprocessing, history, vocabulary, and settings.
- `VoiceFlowKeyboardExtension`: custom keyboard extension for inserting prepared text into the currently active text field.
- Shared extension-safe code for models, store contracts, formatting rules, and lightweight utilities.

The current source of truth is `ROADMAP.md`.

## Current Repository State

This repo is intentionally not scaffolded as an Xcode project yet. Do not create an `.xcodeproj`, Swift package, app target, or keyboard extension target unless the user explicitly asks for code scaffolding.

The user plans to create the initial Xcode project manually in Xcode.

## Product Constraints

Respect these iOS constraints when making technical decisions:

- VoiceFlow cannot replace Apple's system dictation microphone button.
- VoiceFlow cannot intercept normal Apple dictation output.
- VoiceFlow should use its own microphone button inside a custom keyboard UI.
- Recording and `SFSpeechRecognizer` belong in the containing app, not inside the Keyboard Extension.
- The Keyboard Extension inserts text through `UITextDocumentProxy.insertText(...)`.
- The containing app and Keyboard Extension communicate through App Groups.
- Secure Fields, Phone Pads, and apps that disable third-party keyboards must be handled as expected iOS limits, not worked around with private APIs.

## Implementation Preferences

- Prefer Swift and SwiftUI for the containing app.
- Prefer UIKit / `UIInputViewController` for the Keyboard Extension.
- Keep extension-safe code separate from app-only code.
- Use Apple Speech first; treat Whisper/Core ML ASR as a later optional phase.
- Keep MVP behavior explicit and reviewable: manual insert is preferred before auto-insert.
- Add tests around state models, shared store behavior, postprocessing, and insert context rules once code exists.

## Do Not Do

- Do not add private iOS APIs.
- Do not attempt to simulate systemwide keyboard events.
- Do not build a workaround for Secure Fields.
- Do not assume microphone access is available inside the Keyboard Extension.
- Do not introduce a remote LLM path without explicit user approval and a clear privacy note.

## Useful Next Steps After Xcode Project Creation

Once the user creates the Xcode project, Codex should help add:

- App Group entitlement to app and keyboard extension.
- Shared models: `DictationRecord`, `PendingInsert`, `VocabularyEntry`, `VoiceFlowSettings`.
- `SharedStoreClient` for App Group persistence.
- `SpeechEngine` protocol and `AppleSpeechEngine`.
- `PostProcessor` with rule-based normalization.
- Minimal keyboard UI with microphone/open-app button and insert button.
- Onboarding screen explaining keyboard setup, microphone permission, and speech recognition permission.
