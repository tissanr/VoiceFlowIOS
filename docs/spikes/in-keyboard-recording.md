# Phase 0 Spike: In-keyboard Recording

> **Verdict:** Deferred pending real-device run.
> **Date:** 2026-05-15
> **Status:** Harness implemented; manual-device measurements postponed.

## Question

Can the VoiceFlow Keyboard Extension run `AVAudioEngine` plus `SFSpeechRecognizer` on the chosen iOS 17 baseline with Open Access enabled, while staying inside the keyboard extension memory and latency budgets?

## Method

Added a temporary keyboard-side probe:

- `VoiceFlow/VoiceFlowKeyboard/KeyboardRecordingSpike.swift`
- wired into `VoiceFlow/VoiceFlowKeyboard/KeyboardViewController.swift`

The probe requests Speech Recognition and Microphone permission from the keyboard, starts an `AVAudioSession` in `.record` / `.measurement`, streams microphone buffers through `SFSpeechAudioBufferRecognitionRequest`, and renders live transcript plus metrics in the keyboard UI.

Captured metrics:

- Peak resident memory in the keyboard extension process.
- Tap-to-engine-start latency.
- Tap-to-first-audio-buffer latency.
- Stop-to-final-result latency.
- Live partial and final transcript behavior.

## Runbook

1. Build and install `VoiceFlow` on a real iPhone.
2. Enable the VoiceFlow keyboard in Settings.
3. Enable **Allow Full Access** for the VoiceFlow keyboard.
4. Open a text field in Notes, Mail, Messages, or Safari.
5. Switch to the VoiceFlow keyboard.
6. Tap **Start Spike Recording**.
7. Speak for 10 seconds, then tap **Stop Recording**.
8. Repeat for 5 minutes of repeated 10-second dictations.
9. Record the worst observed peak resident memory, latency numbers, transcript stability, and extension crashes/restarts.

Required test-version matrix from `docs/specs/testing.md`:

| Tier | iOS | Environment | Peak RSS | Tap -> engine | Tap -> first buffer | Stop -> final | Stability |
| --- | --- | --- | ---: | ---: | ---: | ---: | --- |
| Minimum supported | iOS 17.x, latest available 17 patch preferred | Physical iPhone if available; otherwise close with TestFlight / borrowed-device pass before Phase 1 sign-off | TBD | TBD | TBD | TBD | TBD |
| Current shipping | iOS 26.x, latest available patch | Physical iPhone | TBD | TBD | TBD | TBD | TBD |
| Current simulator | iOS 26.4 or newer installed simulator runtime | iPhone simulator | Supporting evidence only | TBD | TBD | TBD | Supporting evidence only |
| Intermediate compatibility | iOS 18.x, latest available patch | Physical device or simulator when available | TBD | TBD | TBD | TBD | TBD |

## Verdict Rules

- **Primary flow viable:** all tested devices stay below 45 MB peak RSS, tap-to-record is below the 600 ms hard ceiling, finalization is below the 2 s hard ceiling, and no extension restart occurs during the 5-minute loop.
- **Device-class dependent:** newer devices pass but the lowest supported device class exceeds memory/latency ceilings or restarts.
- **Not viable:** microphone capture, speech recognition, permissions, or stability fail in the keyboard even with Open Access enabled.

## Current Findings

No real-device finding yet. Simulator runs are not sufficient for this spike because the question is keyboard-extension microphone entitlement, Open Access behavior, memory ceiling, and Speech stability on device.

Manual-device testing was postponed on 2026-05-15. This keeps Phase 0 moving on non-device evaluations, but the primary keyboard recording flow remains an unproven risk until the physical-device pass is resumed.

## Follow-up

After real-device runs:

1. Replace the pending verdict above with viable / not viable / device-class dependent.
2. Update the in-keyboard recording row in `ROADMAP.md`.
3. If viable, extract the probe into the Phase 1 `SpeechEngine` / recording controller shape described in `docs/specs/speech-and-postprocessing.md`.
4. If not viable, mark primary flow as unavailable for affected devices and make fallback flow the default there.
