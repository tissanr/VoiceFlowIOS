# Spec: Speech & Postprocessing

> **Spec status:** Accepted (v3)
> **Implementation status:** In progress (`SpeechEngine` protocol, `SpeechLocaleResolver`, `SpeechRecognitionPolicy`, and iOS `AppleSpeechEngine` implemented in `VoiceFlowShared`; vocabulary `contextualStrings`, correction-pair replacement, vocabulary learning, and Stage 1 normalization (`PostProcessor` / `TextNormalizer`) implemented; custom language model, real-device validation, and partial-transcript persistence on interruption pending; engine choice reopened for the Phase 2.0 WER benchmark; experimental WhisperKit engine selectable in the containing app for that benchmark)
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

VoiceFlow uses Apple's Speech framework (`SFSpeechRecognizer`) for the MVP. The final engine choice is made by the Phase 2.0 ASR quality benchmark, which measures WER on a fixed German / English / mixed corpus across Apple Speech, iOS 26 `SpeechAnalyzer` / `SpeechTranscriber`, WhisperKit, and Parakeet. Non-Apple engines are integrated in Phase 5 only if the benchmark shows a clear advantage, and run in the containing app only. The Phase 0 Speech verdict is documented in [../spikes/apple-speech-locale-availability.md](../spikes/apple-speech-locale-availability.md).

```swift
protocol SpeechEngine {
    func requestPermissions() async throws
    func start(locale: Locale) async throws
    func stop() async throws -> SpeechResult
}
```

| Option | Benefit | Drawback | Decision |
| --- | --- | --- | --- |
| Apple Speech Framework | Fast MVP, native API, low ML complexity | Own recording required, system behavior not fully controllable | **MVP default** |
| Apple Speech On-Device | Local without a custom model | Availability depends on language / device / iOS version | Validate in Phase 0; check `supportsOnDeviceRecognition` per locale |
| Apple `SpeechAnalyzer` / `SpeechTranscriber` (iOS 26) | System model, no bundle cost, works in extension memory budget | iOS 26 only; German quality unverified | Benchmark in Phase 2.0 |
| WhisperKit `large-v3-turbo` (Core ML) | Expected stronger German accuracy (to be measured); vocabulary via initial prompt | Large model (size measured in 2.0), recent devices only, containing app only | Benchmark in Phase 2.0; Phase 5 if it wins |
| Parakeet TDT v3 (FluidAudio / Core ML) | Very fast; 25 European languages incl. German | German quality unverified; containing app only | Benchmark in Phase 2.0 |

### Experimental engine switch (containing app, Phase 2.0)

To run the 2.0 benchmark on real dictations, the containing app's Dictate tab can switch engines via `VoiceFlowSettings.speechEngine` (`apple` default, `whisper`). The keyboard ignores this setting and always uses `AppleSpeechEngine`.

- `WhisperSpeechEngine` lives in the separate `VoiceFlowWhisper` library of the `VoiceFlowShared` package, which only the `VoiceFlow` app target links. The extension-safe `VoiceFlowShared` library does not depend on WhisperKit.
- `WhisperModelManager` (long-lived in `AppModel`) downloads the selected model (`VoiceFlowSettings.whisperModel`: `base`, `small`, `large-v3-turbo`; default `large-v3-turbo`) from `argmaxinc/whisperkit-coreml` on explicit user action in Settings, then keeps one loaded `WhisperKit` instance. An already downloaded model is loaded in the background when the Dictate tab appears; nothing is downloaded automatically. Switching back to Apple unloads it.
- Recording goes to a 16 kHz mono WAV in the temp directory and is transcribed on Stop (no partial results), then deleted. Vocabulary terms are passed as Whisper decoder prompt tokens (max. 50 terms). Postprocessing is the same `PostProcessor` as for Apple Speech.
- Each `DictationRecord` stores the producing `engine`, shown in History, so the same corpus can be compared per engine.
- The model download is the only network access of this path; audio never leaves the device. Settings copy for this path is flagged for human review.

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
