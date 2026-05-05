# Phase 0 Spike: Minimum iOS Investigation

> **Status:** Done
> **Verdict date:** 2026-04-28
> **Decision:** Minimum deployment target is **iOS 17.0**.
> **Persistence decision:** Use **SwiftData in the App Group container** for history and vocabulary; keep `PendingInsert`, reduced settings, and generation counters in App Group suite preferences through `SharedStoreClient`.

## Question

Compare iOS 17, iOS 18, and iOS 26 for the VoiceFlow MVP, then choose the lowest deployment target that does not materially complicate implementation.

The MVP needs:

- Custom Keyboard Extension with optional Open Access.
- App Group data exchange between app and keyboard extension.
- Microphone recording through `AVAudioSession` / `AVAudioEngine`.
- Apple Speech recognition, including runtime checks for on-device availability.
- Local history and vocabulary storage usable from the containing app and lightly readable from the extension.

## Verdict

Choose **iOS 17.0**.

iOS 17 provides the APIs VoiceFlow needs for the MVP:

- `SFSpeechRecognizer` and live-audio recognition are available, with on-device support checked at runtime through `supportsOnDeviceRecognition`.
- `SFSpeechRecognitionRequest.requiresOnDeviceRecognition` and `addsPunctuation` are available before iOS 17.
- `SFSpeechLanguageModel` and `customizedLanguageModel` are available starting in iOS 17 if custom vocabulary biasing becomes useful.
- SwiftData is available starting in iOS 17, including `ModelConfiguration.GroupContainer.identifier(_:)` for App Group-backed storage.
- Custom Keyboard Open Access behavior is unchanged for the MVP: setting `RequestsOpenAccess = true` lets users grant access; without it, the fallback flow remains required.
- `AVAudioSession` recording categories are mature and predate iOS 17.

iOS 18 does not add a required MVP simplification. It improves parts of SwiftData's lower-level store APIs, but the MVP can avoid those by using standard SwiftData models and keeping cross-process handoff state in App Group suite preferences through `SharedStoreClient`.

iOS 26 adds the newer SpeechAnalyzer / SpeechTranscriber / DictationTranscriber family, but adopting iOS 26 would unnecessarily exclude users and does not remove the Phase 0 need to test microphone + speech inside the Keyboard Extension. Those APIs can be evaluated later behind availability checks.

## Comparison

| Area | iOS 17 | iOS 18 | iOS 26 | Decision |
| --- | --- | --- | --- | --- |
| Speech MVP path | `SFSpeechRecognizer`, live recognition, on-device check, punctuation, custom language model APIs available | No required MVP change | New SpeechAnalyzer / transcriber APIs available | Use `SFSpeechRecognizer` for MVP; defer iOS 26 APIs |
| On-device speech | Runtime-dependent by locale/device through `supportsOnDeviceRecognition` | Same MVP requirement | Newer installed/downloadable locale APIs exist for transcribers | Runtime check still mandatory |
| Custom vocabulary | `SFSpeechLanguageModel` and `customizedLanguageModel` available | Same MVP path | Adds newer weighting/customization knobs | Postprocessing vocabulary remains MVP default |
| Keyboard Extension | Custom keyboard + Open Access model supports required architecture | No known MVP simplification | No required MVP simplification | Keep dual-flow design |
| App Group handoff | App Group suite preferences and containers are sufficient | Same | Same | Use generation-counter protocol through `SharedStoreClient` |
| History/vocabulary storage | SwiftData available with App Group configuration | More lower-level SwiftData APIs, not required | More SwiftData APIs, not required | Use SwiftData for history/vocabulary |
| Audio session | `record` / `playAndRecord` categories available and mature | Same | Same plus newer unrelated capabilities | No reason to raise target |

## Storage Decision

Use **SwiftData** for `DictationRecord` and `VocabularyEntry` in the App Group container.

Rationale:

- SwiftData is available on iOS 17 and can be configured for an App Group container.
- It avoids adding a SQLite wrapper dependency during Phase 0.
- The Keyboard Extension only needs lightweight reads, not long-running writes or full-history queries.
- The contentious cross-process object, `PendingInsert`, stays out of SwiftData and uses the mandatory generation-counter protocol through `SharedStoreClient`.

Guardrail:

- If the App Group store spike shows SwiftData is unreliable for app/extension access patterns, switch history and vocabulary to shared SQLite before Phase 1.

## Sources

- Apple Developer Documentation: [Creating a custom keyboard](https://developer.apple.com/documentation/UIKit/creating-a-custom-keyboard)
- Apple Developer Documentation: [Configuring open access for a custom keyboard](https://developer.apple.com/documentation/uikit/configuring-open-access-for-a-custom-keyboard)
- Apple Developer Documentation: [SFSpeechRecognizer.supportsOnDeviceRecognition](https://developer.apple.com/documentation/Speech/SFSpeechRecognizer/supportsOnDeviceRecognition)
- Apple Developer Documentation: [Speech framework](https://developer.apple.com/documentation/speech/)
- Apple Developer Documentation: [DictationTranscriber](https://developer.apple.com/documentation/speech/dictationtranscriber)
- Apple Developer Documentation: [Preserving your app's model data across launches](https://developer.apple.com/documentation/swiftdata/preserving-your-apps-model-data-across-launches)
- Apple Developer Documentation: [UserDefaults.init(suiteName:)](https://developer.apple.com/documentation/foundation/userdefaults/init%28suitename%3A%29)
- Apple Developer Documentation: [FileManager.containerURL(forSecurityApplicationGroupIdentifier:)](https://developer.apple.com/documentation/foundation/filemanager/containerurl%28forsecurityapplicationgroupidentifier%3A%29)
- Apple Developer Documentation: [AVAudioSession.playAndRecord](https://developer.apple.com/documentation/avfaudio/avaudiosessioncategoryplayandrecord)
- Local SDK check: Xcode iOS 26.4 SDK headers and Swift interfaces confirm `supportsOnDeviceRecognition` and `requiresOnDeviceRecognition` are available from iOS 13, Speech custom language model APIs from iOS 17, and SwiftData core model/container APIs from iOS 17.
