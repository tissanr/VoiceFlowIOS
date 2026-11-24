# Spec: Speech & Postprocessing

> **Spec status:** Accepted (v4 — selectable engines: classic Apple Speech, iOS 26 `SpeechAnalyzer`, and Parakeet / Whisper in the containing app)
> **Implementation status:** In progress (`SpeechEngine` protocol, `SpeechLocaleResolver`, `SpeechRecognitionPolicy`, `MicrophoneCapture`, `SpeechEngineSelection` / `SpeechEngineFactory`, `AppleSpeechEngine`, and iOS 26 `SpeechAnalyzerEngine` implemented in `VoiceFlowShared`; `ParakeetSpeechEngine` + `ParakeetModelStore` in the app-only `VoiceFlowParakeet` package; `WhisperSpeechEngine` + `WhisperModelManager` in the app-only `VoiceFlowWhisper` package; vocabulary `contextualStrings`, correction-pair replacement, vocabulary learning, and Stage 1 normalization (`PostProcessor` / `TextNormalizer`) implemented; custom language model, real-device validation of all engines, and partial-transcript persistence on interruption pending; default engine to be confirmed by the Phase 2.0 WER benchmark)
> **Last updated:** 2026-11-24
> **Owners:** iOS

Audio session, speech recognition strategy, and the postprocessing pipeline that turns raw recognition into shippable text.

---

## Audio session

- **Category:** `.playAndRecord` or `.record`.
- **Options:** `.allowBluetooth`, `.duckOthers`, `.interruptSpokenAudioAndMixWithOthers`. Avoid abruptly killing the user's background music or podcasts unless required.
- **Activation site:**
  - **Primary flow** — Keyboard Extension activates and deactivates the session. The keyboard must release the session before dismissal.
  - **Fallback flow** — containing app activates and deactivates.
- **Interruptions** (phone call, Siri, Focus mode, headphone unplug): persist the partial transcript to the App Group store before tearing down the session. On resume, present the partial transcript to the user and let them decide to keep / retry.

---

## Speech engine

VoiceFlow ships four engines behind the `SpeechEngine` protocol. The user picks one in Settings (`VoiceFlowSettings.speechEngine`, default `automatic`); `SpeechEngineSelection` resolves the preference per host and never fails — anything not ready falls back to the classic Apple engine. The Phase 2.0 WER benchmark (German / English / mixed corpus) runs these engines side by side in the containing app and confirms or changes the default. The Phase 0 Speech verdict is documented in [../spikes/apple-speech-locale-availability.md](../spikes/apple-speech-locale-availability.md).

```swift
protocol SpeechEngine {
    var contextualStrings: [String] { get set }
    func requestPermissions() async throws
    func start(locale: Locale) async throws
    func stop() async throws -> SpeechResult
    func cancel()
}
```

| Engine (`SpeechEngineKind`) | Implementation | Hosts | Notes |
| --- | --- | --- | --- |
| `appleClassic` | `AppleSpeechEngine` — `SFSpeechRecognizer`, iOS 17+ | Keyboard + app | Only engine with server recognition and custom language models. Fallback for everything else. |
| `appleSpeechAnalyzer` | `SpeechAnalyzerEngine` — `SpeechAnalyzer` + `SpeechTranscriber` (`.progressiveTranscription`), iOS 26+ | Keyboard + app | Newer on-device system model, no bundle cost. Used only when `SpeechTranscriber.isAvailable`, the locale is supported, and its assets are installed (`AssetInventory`). Public FLEURS runs report roughly half the German WER of the classic recognizer; to be confirmed in 2.0. Keyboard memory with the model loaded is unverified on device. |
| `parakeet` | `ParakeetSpeechEngine` — NVIDIA Parakeet Ultra (post-trained TDT 0.6B v3, 25 European languages) via FluidAudio / Core ML | **Containing app only** | Batch: transcribes on `stop()`, no partial results. Models (~650 MB) are downloaded only on explicit user action in Settings. Lives in the separate `VoiceFlowParakeet` package, which the keyboard target never links. |
| `whisper` | `WhisperSpeechEngine` — OpenAI Whisper via WhisperKit 1.1.1 / Core ML; model `VoiceFlowSettings.whisperModel`: `base` (~150 MB), `small` (~480 MB), `large-v3-turbo` (~632 MB, default) | **Containing app only** | Batch: records a 16 kHz mono WAV in the temp directory, transcribes on `stop()`, then deletes it. Vocabulary goes in as decoder prompt tokens (max. 50 terms). `automatic` locale mode lets Whisper detect the language (copes with German / English mixes). `WhisperModelManager` (long-lived in `AppModel`) downloads from `argmaxinc/whisperkit-coreml` when the user taps *Download* in Settings or dictates for the first time after choosing Whisper, keeps one loaded instance, loads an already downloaded model in the background when Dictate appears, and unloads it when another engine is chosen. Model files are excluded from backup. Early device use: `base` already works well for German dictation — measure in 2.0 against the larger variants. |
| `automatic` (default) | — | Keyboard + app | `SpeechAnalyzer` when ready, else classic. Classic when the user allows server recognition and does not prefer on-device. Never picks an app-only engine. |

Each `DictationRecord` stores the engine that actually ran (`engine`, after fallback), shown in History, so the same corpus can be compared per engine. Records and settings from builds before engine selection (`"apple"`) still decode: the record as `appleClassic`, the setting as `automatic`.

### Engine selection

- **Keyboard Extension:** `SpeechEngineFactory.makeEngine(host: .keyboardExtension)`. Parakeet and Whisper resolve to the best Apple engine. `SpeechAnalyzer` is used only if its assets are already installed — the keyboard never waits on or starts an asset download.
- **Containing app:** `host: .containingApp`, with an app-engine provider. Parakeet returns an engine only when its models are on disk (else Apple fallback). Whisper downloads / loads the chosen model first (Dictate shows a *preparing model* state with Cancel) and surfaces a load failure instead of falling back silently.
- **Assets:** the containing app's Settings shows the `SpeechTranscriber` asset state for the current dictation language and an *Install* button (Apple's own system asset download). Parakeet models get *Download* / *Delete* buttons; Whisper gets a model picker plus *Download and load* / *Load* / *Delete download*.
- **Shared capture:** Apple, SpeechAnalyzer, and Parakeet use `MicrophoneCapture` (audio session, input tap, level metering, interruption / media-services / route-change detection). `WhisperSpeechEngine` still records with `AVAudioRecorder`; moving it onto `MicrophoneCapture` is a cleanup follow-up.

### Locale handling

- Check `SFSpeechRecognizer.supportedLocales()` and `supportsOnDeviceRecognition` at runtime per locale.
- If the user's locale lacks on-device support and the user has chosen "On-Device only," surface a clear "speech unavailable for this language" message — do not silently fall back to network.
- Locale modes are `automatic`, `german`, and `english`. Explicit defaults are `de-DE` for German and `en-US` for English.
- Mixed German / English dictation is a product goal, but the MVP must not assume one Apple Speech session handles both languages equally. Use postprocessing and vocabulary correction for common mixed-language cleanup.

---

## Postprocessing pipeline

VoiceFlow differentiates through final text quality. Errors are fixed at the source first (vocabulary passed into recognition, engine chosen by measured WER); postprocessing then corrects what recognition still gets wrong.

```text
Vocabulary passed into recognition (contextualStrings / custom LM / Whisper prompt)
  -> Speech raw text
  -> Stage 1 (deterministic): apply known correction pairs, normalize punctuation, whitespace, capitalization
  -> Stage 2 (optional LLM, on-device): punctuation, casing, filler words, spoken self-corrections only; short segments; guided generation
  -> Stage 3 (optional): LLM picks between engine alternatives instead of free correction
  -> guardrails (deviation / similarity / repetition)
  -> final text
  -> learn new correction pairs from any user post-edit
```

### Responsibilities

- Normalize punctuation and whitespace.
- Capitalize sentence starts.
- Correct domain terms and proper nouns from vocabulary.
- Handle mixed German / English dictation better.
- Preserve spoken style; do not freely rewrite content.

### Correction levels

- `minimal` — obvious mistakes only.
- `soft` — punctuation, capitalization, light grammar.
- `medium` — improve readability while preserving content.

User-selectable in Settings; default `soft`.

Stage 1 normalization (`TextNormalizer`, run by `PostProcessor` after correction pairs) maps the levels as follows. It only changes formatting, never words.

| Level | Normalization |
| --- | --- |
| `minimal` | Collapse spaces / tabs, trim lines, keep at most one blank line; remove spaces before punctuation; collapse duplicated `,` `;` `:` and `..` (an ellipsis `...` is kept). |
| `soft` | `minimal` + a space after `,` `;` `!` `?` when a letter follows (`.` and `:` are skipped for abbreviations, domains, times; digits for decimal commas); capitalize sentence starts **inside** the text, except after known abbreviations (`z.B.`, `bzw.`, `e.g.`, `vs.`, …), single-letter initials, and ellipses. |
| `medium` | `soft` + a terminal period when the text ends with a letter or digit. |

The first letter of the dictation is not changed: whether it starts a sentence depends on the text before the cursor, which `InsertContextPlanner` decides at insert time ([keyboard-and-insert.md](keyboard-and-insert.md)).

### Guardrails (must)

- Maximum word-count deviation between raw and corrected.
- Length limit on the correction.
- Similarity ratio between raw and corrected text.
- Repetition filter (no duplicated sentences from a hallucinating model).
- Fallback to raw text whenever a guardrail trips.

The guardrail thresholds are tuning parameters; pick conservative defaults in MVP and tighten with telemetry.

### Vocabulary

Vocabulary is applied at two points:

1. **At recognition time** — Apple Speech has no free-form prompt, but accepts `contextualStrings` on the recognition request and custom language models (`SFCustomLanguageModelData`, iOS 17+). Whisper takes an initial prompt with the glossary.
   - **Implemented:** `SpeechEngine.contextualStrings`; callers pass `VocabularyCorrector.recognitionHints(from:)` — the `correction` of every active entry, deduplicated, most used first, capped at 100.
   - Per engine: `AppleSpeechEngine` sets them on the recognition request. `SpeechAnalyzerEngine` passes them as `AnalysisContext.contextualStrings[.general]`; whether `SpeechTranscriber` honors them is unverified (Phase 2.0). `WhisperSpeechEngine` passes up to 50 as decoder prompt tokens. `ParakeetSpeechEngine` ignores them — TDT has no prompt; FluidAudio's CTC keyword boosting (second ~110M encoder, batch only) is a possible follow-up. Stage 1 correction pairs apply to every engine.
   - **Pending:** custom language model. It must be prepared in the containing app (slow) and handed to the keyboard via the App Group; on-device recognition only.
2. **After recognition** — deterministic correction pairs in Stage 1.
   - **Implemented:** `VocabularyCorrector.apply` replaces active `heard` phrases (case-insensitive, whole words, flexible whitespace, longest first) and keeps sentence-start capitalization. Applied entry IDs bump `useCount`. Normalization then runs on the corrected text (see *Correction levels*).

Errors fixed at the source beat errors fixed by an LLM, which can only guess.

#### Learning

`VocabularyLearner` aligns the recognized text with the user's corrected text word by word (LCS) and keeps a replaced stretch as a candidate pair only if both sides have 1–3 words and it plausibly is a misrecognition: letters identical apart from spacing / case (`voice flow` → `VoiceFlow`), or normalized Levenshtein similarity ≥ 0.5 (`Cuba Netis` → `Kubernetes`, `Meier` → `Maier`). Rewrites (`gestern` → `heute`), pure insertions / deletions, punctuation-only changes, and sentence-start capitalization are ignored.

Sources:

- **History edit** in the containing app — the user corrects a dictation and saves.
- **Keyboard post-edit** — see [keyboard-and-insert.md](keyboard-and-insert.md) → *Learning from post-edits*. Controlled by `VoiceFlowSettings.learnFromKeyboardEdits` (default on).

Learning is automatic, activation is not: every candidate is stored as a **suggestion** that the user accepts or declines in the Words screen. Declined pairs are remembered and never re-suggested.

---

## Cross-references

- Where the result lands and how it crosses processes: [data-and-storage.md](data-and-storage.md)
- How the result is inserted: [keyboard-and-insert.md](keyboard-and-insert.md)
- Permissions and privacy posture for microphone + speech: [privacy-and-app-review.md](privacy-and-app-review.md)
