# Workflow: build-test

Build and test what a change touches, then run the guardrail checks. Commands are canonical in [`docs/specs/build-and-ci.md`](../../specs/build-and-ci.md); if they differ, that spec wins — fix this file.

## Steps

1. **Shared package** (always, fast, also what CI runs):

   ```sh
   cd VoiceFlow/VoiceFlowShared && swift build && swift test
   ```

2. **Xcode project** (when anything under `VoiceFlow/VoiceFlow`, `VoiceFlow/VoiceFlowKeyboard`, the test targets, or `project.pbxproj` changed). Pick an installed simulator first:

   ```sh
   xcrun simctl list devices available | grep -E 'iPhone'
   xcodebuild -project VoiceFlow/VoiceFlow.xcodeproj -scheme VoiceFlow \
     -destination 'generic/platform=iOS Simulator' build
   xcodebuild -project VoiceFlow/VoiceFlow.xcodeproj -scheme VoiceFlow \
     -destination 'platform=iOS Simulator,name=<installed iPhone>' test
   ```

   Pipe through `tail -n 50` or `xcbeautify` if available; report the failing test names and the first error, not the whole log.

3. **Guardrails:**

   ```sh
   scripts/agent-checks/run-all.sh
   ```

## Reporting

State exactly what ran and what passed or failed, with the failing output. If a step was skipped (no simulator, no Xcode, signing), say so — never report it as passed. Real-device behavior (recording, Open Access, insertion in host apps, memory) cannot be verified in the simulator; name it as unverified.
