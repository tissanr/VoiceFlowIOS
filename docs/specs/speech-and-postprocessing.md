# Spec: Speech & Postprocessing

> **Spec status:** Accepted (v1)
> **Implementation status:** Not started (Phase 0 pending)
> **Last updated:** 2026-04-28
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

VoiceFlow uses Apple's Speech framework first. Whisper / Core ML remains a later alternative if Apple Speech is insufficient for quality, offline availability, mixed-language dictation, or privacy.

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
| Whisper / Core ML | Full control, consistent offline story | Model size, battery, memory, latency, conversion work | Phase 5 only with proven need |

### Locale handling

- Check `SFSpeechRecognizer.supportedLocales()` and `supportsOnDeviceRecognition` at runtime per locale.
- If the user's locale lacks on-device support and the user has chosen "On-Device only," surface a clear "speech unavailable for this language" message — do not silently fall back to network.

---

## Postprocessing pipeline

VoiceFlow differentiates primarily through text quality after recognition, not through the recognition itself.

```text
Speech raw text
  -> apply known correction pairs (vocabulary)
  -> normalize punctuation, whitespace, capitalization
  -> apply correction-level rules (or LLM, if enabled)
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

### Guardrails (must)

- Maximum word-count deviation between raw and corrected.
- Length limit on the correction.
- Similarity ratio between raw and corrected text.
- Repetition filter (no duplicated sentences from a hallucinating model).
- Fallback to raw text whenever a guardrail trips.

The guardrail thresholds are tuning parameters; pick conservative defaults in MVP and tighten with telemetry.

### Vocabulary

Apple Speech cannot be controlled with a free-form initial prompt like Whisper. Vocabulary is therefore applied **after** recognition. New correction pairs are learned from user post-edits in the review screen, never silently in the background.

---

## Cross-references

- Where the result lands and how it crosses processes: [data-and-storage.md](data-and-storage.md)
- How the result is inserted: [keyboard-and-insert.md](keyboard-and-insert.md)
- Permissions and privacy posture for microphone + speech: [privacy-and-app-review.md](privacy-and-app-review.md)
