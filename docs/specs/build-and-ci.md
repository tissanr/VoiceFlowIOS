# Spec: Build & CI

> **Spec status:** Accepted (v1)
> **Implementation status:** Not started (manual local builds work; CI not set up)
> **Last updated:** 2026-04-28
> **Owners:** iOS

Local build flow, CI pipeline, and the code-signing constraints that come with running two targets in one team.

---

## Local builds

```sh
# Simulator
xcodebuild \
  -scheme VoiceFlow \
  -destination 'generic/platform=iOS Simulator' \
  build

# Device (requires team + provisioning)
xcodebuild \
  -scheme VoiceFlow \
  -destination 'generic/platform=iOS' \
  build
```

Tests:

```sh
xcodebuild \
  -scheme VoiceFlow \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  test
```

---

## CI pipeline

| Phase | Required CI |
| --- | --- |
| Phase 0 | Build + unit tests on every push. |
| Phase 1 | Same. UI tests added but not yet required to pass. |
| Phase 3 | UI tests required to pass on every PR. |
| Phase 4 | Performance budgets (latency / memory smoke tests) required to pass. |
| Phase 6 | Release pipeline (fastlane → TestFlight → App Store Connect). |

Default CI host: GitHub Actions. Concrete workflow file added in Phase 0.

---

## Code signing

- **Team:** `me.tissanr` for both targets.
- Containing app and keyboard extension must use **provisioning profiles that include the App Group entitlement** `group.com.voiceflow.shared`.
- The keyboard extension's profile does not need a separate microphone entitlement; the entitlement comes from the keyboard extension's `Info.plist` (`NSMicrophoneUsageDescription`) plus `RequestsOpenAccess`.
- Bundle IDs:
  - Containing app: `me.tissanr.VoiceFlow`
  - Keyboard extension: `me.tissanr.VoiceFlow.VoiceFlowKeyboard`

The keyboard extension bundle ID **must remain a child** of the containing app's bundle ID (the App Store enforces this for app extensions).

---

## fastlane

Introduced in Phase 6 for App Store submission. Until then, releases are manual via Xcode Organizer.

---

## Cross-references

- Why the App Group entitlement matters and the ID to use: [data-and-storage.md](data-and-storage.md)
- App Review narrative — what the reviewer will ask before signing off: [privacy-and-app-review.md](privacy-and-app-review.md)
