# Phase 0 Spike: Open Access Behavior

> **Date:** 2026-05-15
> **Status:** Postponed until after the Audio Interruption spike
> **Scope:** `RequestsOpenAccess`, keyboard Full Access detection, and keyboard-to-app `openURL` behavior.

## Question

Which features actually depend on custom-keyboard Open Access, and does the fallback posture remain valid when Open Access is declined?

## Harness

The keyboard spike UI now exposes:

- `hasFullAccess` state from `UIInputViewController`.
- An "Open VoiceFlow" action that calls `extensionContext?.open(URL(string: "voiceflow://record")!)`.
- A visible success / failure result for the open-URL attempt.

The containing app now registers the `voiceflow://` URL scheme and displays the last opened URL in the scaffold UI. This makes the open-URL attempt observable instead of relying on console output.

## Current automated findings

- `VoiceFlowKeyboard/Info.plist` has `RequestsOpenAccess = true`, so iOS can show the Allow Full Access toggle.
- The containing app has a `voiceflow` URL scheme registration.
- The app target and keyboard extension build on the iOS 17.5 simulator with the harness in place.

## Manual validation matrix

This matrix is postponed until the Audio Interruption spike has a harness and manual-device procedure. Open Access testing still needs to run before Phase 1 sign-off, but the next device pass should first validate interruption cleanup so microphone behavior is tested with the right instrumentation in place.

Run these checks from a host text field with the VoiceFlow keyboard selected:

| Open Access | Check | Expected observation |
| --- | --- | --- |
| Off | Keyboard status | `hasFullAccess` reports off. |
| Off | Open VoiceFlow | Record whether `extensionContext.open` reports success or failure and whether the app opens. |
| Off | Local Record | Record whether microphone permission can be requested and whether `AVAudioEngine` starts. |
| On | Keyboard status | `hasFullAccess` reports on. |
| On | Open VoiceFlow | Record whether `extensionContext.open` reports success and whether `voiceflow://record` reaches the app. |
| On | Local Record | Record whether microphone permission can be requested and whether `AVAudioEngine` starts. |

Run the matrix on a physical iPhone before Phase 1 sign-off. Simulator results are useful for URL plumbing, but not authoritative for microphone-in-keyboard behavior.

## Provisional verdict

The dual-flow posture remains correct:

- Open Access should stay optional, not required at install time.
- The keyboard can visibly detect and explain Full Access state.
- The fallback containing-app flow is still required because Open Access and microphone behavior need real-device proof.

This spike is not complete until the manual validation matrix records observed behavior with Open Access both off and on.

## Verification

Command:

```sh
swift test
```

Result on 2026-05-15: passed from `VoiceFlow/VoiceFlowShared`.

Build:

```text
VoiceFlow scheme, iPhone SE (3rd generation), iOS 17.5 simulator
```

Result on 2026-05-15: passed.
