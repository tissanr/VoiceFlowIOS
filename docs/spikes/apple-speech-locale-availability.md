# Phase 0 Spike: Apple Speech Locale Availability

> **Verdict:** Apple Speech remains the MVP speech engine; German and English are launch locales; on-device support is runtime-gated per locale.
> **Date:** 2026-05-15
> **Status:** Done for API and product strategy; real recording quality remains part of the deferred physical-device spike.

## Question

Can VoiceFlow use Apple's Speech framework for the MVP across German, English, and mixed German / English dictation, while preserving a local-first privacy posture?

## Decision

Use **`SFSpeechRecognizer`** as the MVP speech engine.

Launch locale modes:

- `automatic`
- `german`
- `english`

For explicit modes, use stable regional defaults:

- German: `de-DE`
- English: `en-US` initially, with `en-GB` eligible later if user settings need it.

For `automatic`, start from `Locale.current` when it maps to a supported recognizer; otherwise fall back to the user's selected app language or English. Mixed German / English dictation is supported as a product goal, but it is not treated as a guarantee that Apple Speech will recognize both languages equally in one recognition session. The MVP should rely on postprocessing and vocabulary correction to clean up common mixed-language mistakes.

On-device recognition is **preferred, not assumed**. At runtime, every selected locale must check:

- `SFSpeechRecognizer.supportedLocales()`
- `SFSpeechRecognizer(locale:).supportsOnDeviceRecognition`
- `SFSpeechRecognizer(locale:).isAvailable`

If the user has chosen local-only / on-device-only behavior and the selected locale does not support on-device recognition, show a clear unavailable state. Do not silently downgrade to network recognition.

## Evidence

Local SDK check against Xcode iOS 26.5 SDK headers:

- `SFSpeechRecognizer.supportedLocales()` is available.
- `SFSpeechRecognizer.supportsOnDeviceRecognition` is available from iOS 13.
- `SFSpeechRecognitionRequest.requiresOnDeviceRecognition` is available from iOS 13.
- `SFSpeechRecognitionRequest.addsPunctuation` is available from iOS 16.
- `SFSpeechRecognitionRequest.customizedLanguageModel` is available from iOS 17.

This matches the iOS 17.0 deployment target selected in [min-ios-investigation.md](min-ios-investigation.md).

References:

- Apple Developer Documentation: [`SFSpeechRecognizer`](https://developer.apple.com/documentation/speech/sfspeechrecognizer)
- Apple Developer Documentation: [`SFSpeechRecognitionRequest.requiresOnDeviceRecognition`](https://developer.apple.com/documentation/speech/sfspeechrecognitionrequest/requiresondevicerecognition)
- Apple Developer Documentation: [`SFSpeechRecognizer.supportsOnDeviceRecognition`](https://developer.apple.com/documentation/speech/sfspeechrecognizer/supportsondevicerecognition)

## Implementation Requirements

Phase 1 `AppleSpeechEngine` should expose a locale capability check before starting recognition:

```swift
struct SpeechLocaleCapability: Equatable, Sendable {
    var localeIdentifier: String
    var isSupported: Bool
    var isAvailable: Bool
    var supportsOnDeviceRecognition: Bool
}
```

Start behavior:

- If the locale is unsupported, fail before requesting audio.
- If the locale is supported but currently unavailable, show a retryable error.
- If `preferOnDeviceSpeech == true` and `supportsOnDeviceRecognition == true`, set `requiresOnDeviceRecognition = true`.
- If `privacyMode == .localOnly` and on-device recognition is unavailable, fail with a clear local-only unavailable message.
- If network speech is allowed later, the UI must show that the active mode is not fully local.

The recognition request should set:

- `shouldReportPartialResults = true`
- `addsPunctuation = true`
- `requiresOnDeviceRecognition` only when the selected locale supports it and the user's privacy settings require/prefer it.

## Non-goals

- Do not adopt iOS 26 `SpeechAnalyzer`, `SpeechTranscriber`, or `DictationTranscriber` for MVP.
- Do not ship Whisper / Core ML in MVP.
- Do not use remote LLMs for recognition.
- Do not send audio to any remote service.

## Remaining Risk

This verdict confirms API fit and product strategy, not recognition quality. Real microphone capture, latency, memory, and recognition quality inside the Keyboard Extension remain covered by the deferred [in-keyboard-recording.md](in-keyboard-recording.md) physical-device spike.

## Follow-up

1. Add `AppleSpeechEngine` behind the `SpeechEngine` protocol in Phase 1.
2. Add unit tests for locale selection and on-device-only failure states.
3. Add UI states for unsupported locale, unavailable recognizer, and local-only unavailable.
4. Revisit iOS 26 transcriber APIs only after the MVP Apple Speech path is proven insufficient.
