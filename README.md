<<<<<<< HEAD
# VoiceFlowIOS
=======
# VoiceFlow iOS

VoiceFlow iOS is planned as a keyboard-centered dictation and text-formatting app.

The app should let a user start a VoiceFlow dictation flow while working in another iOS app, format the recognized text, and insert the final result into the active text field through a custom keyboard extension.

## Current Status

This repository currently contains the product and engineering specification only.

- Main specification: [`ROADMAP.md`](ROADMAP.md)
- Codex guidance: [`AGENTS.md`](AGENTS.md)

The initial Xcode project is intentionally not generated yet. It should be created manually in Xcode before implementation begins.

## Intended Architecture

```text
VoiceFlowApp
  -> recording
  -> Apple Speech transcription
  -> postprocessing
  -> history, vocabulary, settings
  -> App Group store

VoiceFlowKeyboardExtension
  -> VoiceFlow keyboard UI
  -> reads pending insert from App Group store
  -> inserts text via UITextDocumentProxy.insertText(...)
```

## Key Product Decision

VoiceFlow does not replace Apple's system dictation button and cannot intercept Apple dictation output.

The MVP should use a custom VoiceFlow keyboard plus a containing app:

1. User opens the VoiceFlow keyboard in a target app.
2. User starts a VoiceFlow dictation flow.
3. The containing app records and transcribes with Apple Speech.
4. VoiceFlow formats the text.
5. The keyboard extension inserts the final text into the active field.

## Suggested First Implementation Milestone

After creating the Xcode project:

- Add containing app target.
- Add custom keyboard extension target.
- Enable App Groups for both targets.
- Add shared data models and a small shared store.
- Build a minimal insert flow using `UITextDocumentProxy.insertText(...)`.
- Add Apple Speech recording in the containing app.
>>>>>>> 43bff93 (Set up Codex project files and iOS roadmap)
