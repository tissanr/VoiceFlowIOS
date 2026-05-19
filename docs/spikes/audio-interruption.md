# Phase 0 Spike: Audio Interruption

> **Date:** 2026-05-19
> **Status:** In progress
> **Scope:** Audio-session interruption, route-change, and lifecycle behavior during keyboard recording.

## Question

Can VoiceFlow detect and cleanly recover from interruptions while recording in the Keyboard Extension and the containing-app fallback flow?

## Harness

The keyboard recording spike now observes:

- `AVAudioSession.interruptionNotification`
- `AVAudioSession.routeChangeNotification`
- `AVAudioSession.mediaServicesWereLostNotification`
- `AVAudioSession.mediaServicesWereResetNotification`
- Keyboard view appear / disappear lifecycle events

The keyboard spike UI shows the five most recent audio events alongside memory and timing metrics. On interruption start, the harness stops recording and cleans up the audio engine so a partial capture is not left running invisibly.

## Current automated findings

- The app and keyboard extension build with the interruption harness.
- The shared package tests still pass.
- Simulator verification can prove the harness compiles and the UI can display event state, but it cannot prove call, Siri, Focus, Bluetooth, or real microphone interruption behavior.

## Manual validation matrix

Run this matrix on a physical iPhone with the VoiceFlow keyboard selected in a host text field:

| Scenario | Expected observation |
| --- | --- |
| Incoming phone call during recording | Interruption begins, recording stops, event is visible, no silent background capture continues. |
| Phone call dismissed | Interruption ends, event is visible, user can start a fresh recording. |
| Siri invoked during recording | Interruption begins or route changes, recording stops, event is visible. |
| Focus / system alert while recording | Event behavior is recorded; no crash or hidden recording continues. |
| Headphones / Bluetooth input disconnected | Route-change event records `old device unavailable`; recording either continues with valid input or stops visibly. |
| New audio input connected | Route-change event records `new device available`; user can start or continue according to observed system behavior. |
| Keyboard dismissed during recording | Lifecycle event appears and recording cleanup is visible. |
| Containing-app fallback recording interrupted | Same cleanup expectations apply in the fallback flow when that implementation exists. |

## Provisional verdict

The keyboard now has enough instrumentation to run a meaningful device interruption pass. This spike is not complete until the manual matrix records observed behavior on a physical iPhone.

Open Access manual validation is intentionally postponed until after this interruption matrix, so microphone and `openURL` behavior can be tested with interruption instrumentation already in place.

## Verification

```sh
swift test
```

Result on 2026-05-19: passed from `VoiceFlow/VoiceFlowShared`.

```text
VoiceFlow scheme, iPhone SE (3rd generation), iOS 17.5 simulator
```

Result on 2026-05-19: passed.

Known follow-up: the build still reports existing Swift concurrency warnings in the recording spike's Speech and timer callbacks. They do not block the harness build, but should be cleaned up before moving the recording spike beyond Phase 0.
