# VoiceFlow iOS — Roadmap & Product Specification

> **Last updated:** 2026-04-28
> **Purpose:** Canonical iOS product specification for VoiceFlow as a keyboard-centered dictation and text-formatting app.

---

## Product Goal

VoiceFlow iOS lets users dictate text while working in other iOS apps, improves the recognized raw transcript, and inserts the final text into the currently selected text field.

The architecture has a **primary flow** (recording inside the keyboard extension, requires Open Access) and a **fallback flow** (containing app records, user returns manually). Both flows end with `UITextDocumentProxy.insertText(...)` into the active field.

VoiceFlow does not replace Apple's system dictation. VoiceFlow is enabled as a custom keyboard and writes into the active text field through the official keyboard APIs.

---

## iOS Assumptions

### What iOS Allows

- A Custom Keyboard Extension can be enabled systemwide as a keyboard.
- When VoiceFlow is the active keyboard, it can insert text into the currently selected text field using `UITextDocumentProxy.insertText(...)`.
- The Keyboard Extension can read limited context around the cursor:
  - `documentContextBeforeInput`
  - `documentContextAfterInput`
- The containing app and Keyboard Extension can exchange data through App Groups.
- With **Open Access** ("Allow Full Access") enabled, the Keyboard Extension may use network APIs, `openURL` from the extension, and a richer App Group access pattern. Microphone access from a Keyboard Extension is also conditional on Open Access.

### What iOS Does Not Allow

- No global push-to-talk hotkey.
- No systemwide simulation of keyboard input into arbitrary apps.
- No registration as a replacement provider for Apple's system dictation service.
- No interception of normal Apple dictation output before insertion.
- No availability in every field: Secure Fields, Phone Pads, and apps that disable third-party keyboards can exclude VoiceFlow.
- **No programmatic "Return to App":** iOS does not allow the app to force the user back to the previous application. The user must use the system "Back" breadcrumb or the App Switcher.

### What is conditional and must be validated in Phase 0

- **Microphone + `SFSpeechRecognizer` inside a Keyboard Extension.** Common iOS folklore says this is unreliable; we are explicitly challenging that with a Phase 0 spike on the chosen iOS baseline. Open Access is assumed required.
- **`openURL` from a Keyboard Extension** typically requires Open Access. Phase 0 must confirm.

---

## Architectural Reframe — Dual Flow

### Primary flow (Open Access granted)

```text
User focuses a text field in the target app
  -> User switches to VoiceFlow Keyboard
  -> User taps microphone button in the keyboard
  -> Keyboard Extension starts AVAudioEngine + SFSpeechRecognizer
  -> User stops recording
  -> Keyboard transcribes and applies postprocessing
  -> Keyboard previews the result inline
  -> User taps Insert
  -> UITextDocumentProxy.insertText(...)
```

No app switch. No Return Trip.

### Fallback flow (Open Access denied, or in-keyboard recording infeasible on the target device/iOS)

```text
User taps microphone button in the keyboard
  -> Keyboard shows: "Open Full Access for in-keyboard recording, or tap to record in the VoiceFlow app"
  -> Keyboard deep-links to the containing app (or instructs the user to open it)
  -> Containing app records, transcribes, postprocesses
  -> Containing app writes PendingInsert to the App Group store
  -> Containing app shows: "Switch back to <target app> to insert"
  -> User returns manually (breadcrumb or App Switcher)
  -> Keyboard Extension reads PendingInsert and offers Insert
```

The fallback flow is degraded UX. Users are told why and how to upgrade (enable Open Access).

### Why dual flow

- **Honesty:** the Return Trip is fragile; admitting it as a fallback is more honest than making it the default.
- **App Review:** Open Access becomes an *optional improvement*, not a hard requirement, easing reviewer concerns.
- **Privacy posture:** users who decline Open Access still get a working product.

---

## Technical Refinements & Constraints

### Open Access (Full Access) — decision policy

- **Posture:** optional with fallback. The MVP works without Open Access via the fallback flow.
- **Enables:** in-keyboard recording, `openURL` from the keyboard, smoother App Group sync, network access (e.g., remote LLM if ever enabled).
- **Phase 0 must produce:** a written go/no-go on whether the microphone path inside the keyboard is reliable enough on the chosen iOS baseline to be the primary flow.

### App Group Storage Strategy

- **App Group ID:** `group.com.voiceflow.shared` (must match in both targets' entitlements).
- **Low latency, small payloads** (`PendingInsert`, `KeyboardState`): `UserDefaults(suiteName: "group.com.voiceflow.shared")`. Atomic per-key, suitable for extension/app handoffs.
- **High volume** (`DictationRecord`, `VocabularyEntry`): `SwiftData` or shared SQLite file in the App Group container.
- **Generation counter:** every write to `PendingInsert` increments a monotonic counter (see *App Group Concurrency Protocol* below) so the keyboard can detect torn reads.

### Audio Session Management

- **Category:** `.playAndRecord` or `.record`.
- **Options:** `.allowBluetooth`, `.duckOthers`, `.interruptSpokenAudioAndMixWithOthers`. Avoid abruptly killing the user's background music/podcasts unless required.
- **Session activation site:** in the **primary flow** the keyboard extension activates and deactivates the session; in the **fallback flow** the containing app does. The keyboard must release the session before dismissal.
- **Interruptions:** on phone-call / Siri / Focus interruption, persist the partial transcript to the App Group store before tearing down the session.

### Memory Budget (Keyboard Extension)

iOS terminates Keyboard Extensions that exceed roughly 48 MB resident memory. The MVP must not load history, vocabulary, or models eagerly inside the extension.

| Item | Budget | Notes |
| --- | --- | --- |
| Total resident extension memory | < 30 MB sustained, < 45 MB peak | Leave headroom for the system. |
| `PendingInsert` cache | < 8 KB | Single record. |
| Vocabulary loaded in-extension | ≤ 200 entries OR < 64 KB | Lazy-loaded; rest stays in containing app. |
| History loaded in-extension | last 5 entries only | Full history lives only in the app. |
| Speech recognition (primary flow) | measured in Phase 0 spike | If the spike shows we cannot stay under budget with live recognition, we fall back to keyboard→app for that device class. |

The Phase 0 in-keyboard recording spike must measure peak memory on real devices and produce a memory budget verdict.

### App Group Concurrency Protocol

`PendingInsert` is the most contentious shared object. Define one writer, one consumer, and a generation counter:

```text
Keys (UserDefaults, suite group.com.voiceflow.shared):
  pendingInsert.payload        // Codable PendingInsert blob
  pendingInsert.generation     // monotonic Int, incremented on every write
  pendingInsert.consumedGen    // generation last consumed by the keyboard
```

Rules:

- Only the *producing* side (containing app in the fallback flow, keyboard in the primary flow) writes `pendingInsert.payload` and bumps `generation`.
- The keyboard reads only when `generation > consumedGen`.
- After successful insert, the keyboard sets `consumedGen = generation` and writes `consumedAt` into the payload.
- TTL: payloads with `createdAt` older than 10 minutes are considered stale and ignored.
- Tombstone on consume; never delete records mid-flight (the user may re-insert from history).

This eliminates torn reads even though `UserDefaults` synchronization between processes is not instantaneous.

---

## Microphone Button Below The Keyboard

The microphone button below the iOS keyboard belongs to Apple's system dictation. VoiceFlow cannot register itself there as an alternative provider.

`UIInputViewController.hasDictationKey` does not mean VoiceFlow can replace Apple's dictation button. It only controls whether a Custom Keyboard Extension presents its own dictation key inside its own UI, so iOS does not also show a confusing system dictation button while VoiceFlow is active.

Consequence:

- VoiceFlow shows its own microphone button **inside the VoiceFlow keyboard UI**.
- Tapping that button starts the dictation flow (primary or fallback depending on Open Access).
- Final result is inserted via `UITextDocumentProxy.insertText(...)`.

---

## MVP Scope

### Must Have

- Keyboard Extension can insert text into supported text fields.
- Containing app can request microphone and speech-recognition permissions.
- **Primary flow** works end-to-end on the chosen iOS baseline with Open Access enabled.
- **Fallback flow** works end-to-end without Open Access.
- Rule-based postprocessing on the result.
- App Group store with the documented concurrency protocol.
- Secure Field / Phone Pad / disabled-keyboard detection with clipboard fallback (was Phase 4, now MVP — see *Phase Reordering*).
- Error states are shown visibly and never silently dropped.
- Onboarding screen explaining: keyboard activation, microphone permission, speech-recognition permission, Open Access trade-off.
- Numeric performance budgets met (see *Performance Budgets*).
- Accessibility baseline: VoiceOver labels on every interactive element, hit targets ≥ 44×44, Dynamic Type up to `.accessibilityExtraExtraExtraLarge` does not break the layout.

### Should Have

- Simple history list (last 20) in the containing app.
- Manual editing of the final text before saving.
- Context-aware capitalization using `documentContextBeforeInput`.
- Language setting for German / English / Auto, if Apple Speech supports the chosen baseline well enough.

### Not In MVP

- Custom Whisper/Core ML ASR.
- Fully local LLM.
- Automatic insert without user confirmation.
- Advanced analytics.
- iCloud sync.
- Full custom keyboard with all standard keys as a replacement for Apple's keyboard.
- Remote LLM (network-bound) — gated on a separate explicit decision and privacy review.

---

## User Flows

### Flow A — First Setup

```text
User opens VoiceFlow app
  -> App explains keyboard setup, microphone, speech recognition, and the Open Access trade-off
  -> User enables VoiceFlow Keyboard in iOS Settings
  -> User chooses to enable Open Access (recommended) or skip (fallback flow)
  -> User grants microphone permission
  -> User grants speech-recognition permission
  -> App runs a test dictation
  -> App shows: "Keyboard ready (in-keyboard mode)" or "Keyboard ready (handoff mode)"
```

Acceptance: User understands, in plain language, why each permission and Open Access matter, and what changes if Open Access is skipped.

### Flow B (primary) — In-keyboard dictation

```text
User focuses a text field in the target app
  -> User switches to VoiceFlow Keyboard
  -> User taps microphone button
  -> Keyboard records, transcribes, postprocesses
  -> Keyboard previews result inline
  -> User taps Insert
  -> Text is inserted via UITextDocumentProxy.insertText(...)
```

Acceptance: completes without leaving the target app.

### Flow C (fallback) — Handoff dictation

```text
User taps microphone (Open Access disabled)
  -> Keyboard explains: "Recording happens in the VoiceFlow app. Tap to continue."
  -> Containing app opens, records, transcribes, postprocesses
  -> Containing app writes PendingInsert (generation N+1)
  -> User returns to target app via breadcrumb / App Switcher
  -> Keyboard Extension reads PendingInsert and offers Insert
  -> User taps Insert
```

Acceptance: no recognized text is lost across app switches; PendingInsert TTL handled cleanly.

### Flow D — Reinsert latest dictation

```text
User opens VoiceFlow Keyboard
  -> Keyboard shows latest dictation (from App Group store)
  -> User taps Insert
```

Acceptance: works without a new recording.

### Flow E — Unsupported field

```text
User is in Secure Field / Phone Pad / app without third-party keyboards
  -> VoiceFlow detects the condition before recording starts
  -> Keyboard or app explains the limitation in plain language
  -> Final text is placed on the clipboard as fallback
```

Acceptance: never silently fail; never attempt to bypass iOS limits.

---

## State Model

### DictationState

```swift
enum DictationState: String, Codable {
    case idle
    case requestingPermissions
    case recording
    case transcribing
    case processing
    case readyForReview
    case pendingInsert
    case inserted
    case failed
}
```

### KeyboardState

```swift
enum KeyboardState {
    case noSharedAccess
    case ready
    case recording                   // primary flow only
    case transcribing                // primary flow only
    case hasPendingInsert(DictationID)
    case inserting
    case insertUnavailable(reason: InsertUnavailableReason)
}
```

### InsertUnavailableReason

```swift
enum InsertUnavailableReason: String, Codable {
    case noPendingText
    case secureField
    case unsupportedKeyboardType
    case appDisallowsKeyboard
    case sharedStoreUnavailable
    case openAccessRequired
    case unknown
}
```

---

## Target Architecture

```text
VoiceFlowApp (containing app)
  -> RecordingController              // primary path: only used in fallback flow
       AVAudioSession / AVAudioEngine
  -> SpeechEngine                     // AppleSpeechEngine first; protocol allows swap
  -> PostProcessor                    // rules + optional LLM
  -> VocabularyStore                  // domain terms, correction pairs
  -> DictationStore                   // history, status (full)
  -> SettingsStore                    // language, correction level, privacy mode
  -> OnboardingFlow

VoiceFlowKeyboardExtension
  -> KeyboardViewController
       microphone button, Insert, Retry, Cancel, Next-Keyboard (globe)
  -> RecordingController              // primary flow only, gated on Open Access
  -> SpeechEngine                     // shared protocol, lightweight init
  -> PostProcessor                    // shared rule pipeline
  -> TextProxyWriter                  // UITextDocumentProxy.insertText(...)
  -> CursorContextReader              // documentContextBeforeInput / AfterInput
  -> SharedStoreClient                // generation-counter aware
  -> InsertGuard                      // detects Secure Field / Phone Pad / disabled keyboard

Shared (extension-safe Swift package or framework)
  -> Models: DictationRecord, PendingInsert, VocabularyEntry, VoiceFlowSettings
  -> SharedStoreClient (read paths usable from both targets)
  -> PostProcessor rule pipeline
  -> SpeechEngine protocol
```

Code that uses APIs **unavailable** to extensions stays exclusively in the containing app. The shared framework must compile under the extension-safe API subset.

---

## Insert Edge Cases (the boring details that break apps)

`UITextDocumentProxy.insertText(...)` is not a panacea. The MVP must address:

- **Marked text / IME composition.** If a marked-text composition is in flight (CJK input, autocorrect candidate) — clear / commit before inserting.
- **RTL text.** Always insert as logical-order text; never reverse for display.
- **Selection replacement.** When the user has a selection, `insertText` replaces it on most fields, but not all. Document and test.
- **Undo grouping.** Insert as a single undoable transaction. Avoid multiple `insertText` calls for one logical insert.
- **Predictive text overrides.** Some apps consume the input and re-emit something different. Detect via context-after-insert; warn user if the result is suspicious.
- **Masked / formatted fields** (credit cards, phone formats). Result may be silently dropped or reformatted. Detect by re-reading `documentContextBeforeInput` immediately after insert; if no change, fall back to clipboard.
- **Leading whitespace.** If `documentContextBeforeInput` ends without whitespace and the cursor is mid-sentence, prepend a single space; never two.
- **Sentence boundaries.** Capitalize the first character if `documentContextBeforeInput` is empty or ends with `.`, `!`, `?`, `:`, or newline.
- **Trailing punctuation.** If the recognized text already ends with `.!?` and the surrounding context already has terminal punctuation, do not double up.

---

## Data Model

### DictationRecord

```swift
struct DictationRecord: Codable, Identifiable {
    let id: UUID
    let createdAt: Date
    var sourceLocale: String
    var rawText: String
    var processedText: String
    var correctionLevel: CorrectionLevel
    var durationMs: Int
    var wordCount: Int
    var accuracyRatio: Double?
    var state: DictationState
    var insertedAt: Date?
}
```

### PendingInsert

```swift
struct PendingInsert: Codable {
    let dictationID: UUID
    let text: String
    let createdAt: Date
    var consumedAt: Date?
    var expiresAt: Date          // 10 minute TTL
    let generation: Int          // matches pendingInsert.generation key
    let producedBy: ProducerSide // .keyboardExtension or .containingApp
}
```

### VocabularyEntry

```swift
struct VocabularyEntry: Codable, Identifiable {
    let id: UUID
    var heard: String
    var correction: String
    var isEnabled: Bool
    var createdAt: Date
    var lastUsedAt: Date?
    var useCount: Int
}
```

### Settings

```swift
struct VoiceFlowSettings: Codable {
    var localeMode: LocaleMode
    var correctionLevel: CorrectionLevel
    var autoCopyFallback: Bool
    var preferOnDeviceSpeech: Bool
    var allowLLMProcessing: Bool
    var privacyMode: PrivacyMode
}
```

---

## Shared Store Contract

The App Group store (`group.com.voiceflow.shared`) is the central interface between the containing app and the Keyboard Extension. It must remain small, robust, and low-transaction.

### Writers

- **Primary flow:** Keyboard Extension writes `PendingInsert` (with `producedBy = .keyboardExtension`).
- **Fallback flow:** Containing app writes `PendingInsert` (with `producedBy = .containingApp`).
- Containing app writes `DictationRecord`, settings, and vocabulary at any time.

### Readers

- Keyboard Extension reads `PendingInsert`, reduced settings, and vocabulary subset.
- Containing app reads anything.

### Rules

- Concurrency protocol (generation counter, consumedGen tombstone) is mandatory; see *App Group Concurrency Protocol*.
- Keyboard Extension must not trigger long write operations.
- Store access must be fault-tolerant: extensions can be terminated at any time.
- TTL on `PendingInsert` is 10 minutes; older payloads are ignored.

---

## Core Technologies

| Area | Technology |
| --- | --- |
| App UI | SwiftUI |
| Keyboard Extension UI | `UIInputViewController`, UIKit (SwiftUI hosted where stable) |
| Text insertion | `UITextDocumentProxy.insertText(...)` |
| Cursor context | `documentContextBeforeInput`, `documentContextAfterInput` |
| Audio recording | `AVAudioSession`, `AVAudioEngine` |
| Speech recognition (MVP) | `SFSpeechRecognizer`, with `supportsOnDeviceRecognition` check |
| Postprocessing | Rule pipeline + optional local LLM adapter |
| Persistence | SwiftData or SQLite (decided by min-iOS investigation) |
| Extension comms | App Groups, shared container, UserDefaults + (SwiftData / SQLite) |
| Shortcuts | App Intents |
| Later offline ASR | Whisper/Core ML or whisper.cpp/Metal |

---

## Speech Strategy

VoiceFlow uses Apple's Speech framework first. Whisper/Core ML remains a later alternative if Apple Speech is insufficient for quality, offline availability, mixed-language dictation, or privacy.

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
| Apple Speech On-Device | Local without a custom model | Availability depends on language/device/iOS version | Validate in Phase 0 |
| Whisper / Core ML | Full control, consistent offline story | Model size, battery, memory, latency, conversion work | Phase 5, only with proven need |

---

## Postprocessing Strategy

VoiceFlow differentiates primarily through text quality after recognition, not through speech recognition itself.

### Responsibilities

- Normalize punctuation and whitespace.
- Capitalize sentence starts.
- Correct domain terms and proper nouns from vocabulary.
- Handle mixed German/English dictation better.
- Preserve spoken style; do not freely rewrite content.
- Offer correction levels:
  - `minimal` — obvious mistakes only
  - `soft` — punctuation, capitalization, light grammar
  - `medium` — improve readability while preserving content

### Guardrails

- Maximum word-count deviation between raw and corrected.
- Length limit.
- Similarity ratio between raw text and correction.
- Repetition filter.
- Fallback to raw text when correction is uncertain.

### Vocabulary

Apple Speech cannot be controlled with a free-form initial prompt like Whisper. Vocabulary is therefore applied after recognition:

```text
Speech raw text
  -> apply known correction pairs
  -> format with rules / LLM
  -> learn new correction pairs (post-edit)
```

---

## Insert Strategy

The only primary insert path is `UITextDocumentProxy.insertText(...)`. See *Insert Edge Cases* for the must-handle list.

### Before insert

- Read `documentContextBeforeInput`.
- Detect sentence start.
- Add a leading space if the context ends without whitespace and the cursor is mid-sentence.
- Avoid duplicate punctuation.

### After insert

- Set `PendingInsert.consumedAt` and `pendingInsert.consumedGen`.
- Set `DictationRecord.insertedAt`.
- Set keyboard UI to "Inserted".
- Re-read `documentContextBeforeInput`; if no change, the field rejected the insert silently — fall back to clipboard with explanation.

### Fallback

If the keyboard is unavailable or insert appears impossible:

- Copy text to `UIPasteboard`.
- Briefly explain why clipboard was used.
- Never discard text silently.

---

## Permissions And Privacy

### Required Permissions

- **Microphone** — primary flow (in keyboard) and fallback flow (in app).
- **Speech Recognition** — `SFSpeechRecognizer`.
- **Open Access (Full Access)** — *recommended* for primary flow; not required for fallback flow.

### Privacy Rules

- No audio is stored in the MVP except for explicit, opt-in debugging.
- Raw and final text remain local unless an external LLM mode is enabled (off by default).
- If an external LLM is used, the mode must be visible and disableable from the main UI.
- Keyboard Extension reads only the data needed for insert / favorites.
- Secure Fields are not bypassed.

---

## Accessibility

- Every interactive element in the keyboard exposes a VoiceOver label and hint.
- Hit targets ≥ 44×44 pt (Apple HIG).
- Dynamic Type up to `.accessibilityExtraExtraExtraLarge` must not break the keyboard layout. Use scrollable / wrapping layouts instead of clipping.
- Sufficient color contrast (≥ 4.5:1 for text, ≥ 3:1 for UI elements) in both light and dark mode.
- Reduced Motion respected — no purely decorative animations during dictation.
- VoiceOver users must be able to complete *Flow B* (primary) end-to-end without sighted assistance.

---

## Localization

- **Launch languages:** German (de) and English (en). Mixed German/English dictation is a recognized recurring use case.
- **Per-locale Speech availability** must be checked at runtime via `SFSpeechRecognizer.supportedLocales()` and `supportsOnDeviceRecognition`. If on-device is unavailable for the user's locale, the UI announces this clearly.
- **String catalogs:** `Localizable.xcstrings` (Xcode 15+) for both targets. The keyboard extension and the containing app share a string-keys convention.
- **Number/date formatting** uses `Locale.current`.
- **Right-to-left text:** see *Insert Edge Cases*. RTL is a Phase 4 hardening target; the MVP must not crash or render incorrectly in RTL contexts but is not required to ship Arabic/Hebrew dictation.

---

## Telemetry & Crash Reporting

- **Crash reporting:** required from Phase 0. Choose between Apple's MetricKit (privacy-friendly, no network) and a third-party (Sentry, Firebase Crashlytics) — decided in Phase 0. Default preference: MetricKit, because the keyboard extension cannot reliably make network calls without Open Access.
- **Diagnostic events:** local-only ring buffer in the App Group store, viewable in Settings → Diagnostics. No silent network telemetry.
- **Extension crash visibility:** the containing app inspects MetricKit reports on launch and surfaces a "Last keyboard error" in onboarding/settings.

---

## Performance Budgets (numeric)

| Metric | Target | Hard ceiling |
| --- | --- | --- |
| Cold app launch (containing app) | < 700 ms to first interactive frame | 1.2 s |
| Keyboard load (first appearance after activation) | < 250 ms | 500 ms |
| Tap-to-record start latency (primary flow) | < 300 ms | 600 ms |
| End-of-recording → final text on screen | < 800 ms for ≤ 10 s of audio | 2 s |
| Insert latency (Insert tap → text appears) | < 100 ms | 250 ms |
| Keyboard extension peak memory | < 45 MB | 48 MB termination boundary |
| Containing app peak memory during recording | < 120 MB | 200 MB |
| Battery cost per minute of recording | < 1.5 % on iPhone 13 | 3 % |

These numbers are MVP exit criteria. They will be re-validated in Phase 4.

---

## CI, Code Signing & Build Pipeline

- **Local builds:** `xcodebuild -scheme VoiceFlow -destination "generic/platform=iOS Simulator"` and a device variant.
- **CI:** GitHub Actions (or alternative) running build + unit tests on every push by Phase 1. UI tests added by Phase 3.
- **Code signing:** the containing app and the keyboard extension share team `me.tissanr`. Provisioning profiles for both targets must include the App Group entitlement `group.com.voiceflow.shared`. The keyboard extension's profile does not require the microphone entitlement on its own; the entitlement comes from the keyboard extension's `Info.plist` and `RequestsOpenAccess` flag.
- **fastlane:** introduced in Phase 6 for App Store submission.

---

## App Review Narrative

Custom keyboards combined with microphone access and (optionally) network-bound LLMs face elevated App Review scrutiny. The narrative must be drafted in **Phase 0** and refined throughout:

- **Why a custom keyboard?** Apple's system dictation does not allow VoiceFlow to format, correct, or apply user vocabulary before insertion. VoiceFlow's value is post-recognition processing.
- **Why microphone?** Recording is owned by VoiceFlow; we do not share or upload audio.
- **Why Open Access (when requested)?** To enable in-keyboard recording and avoid forcing users into the fallback flow. The dual-flow design exists specifically so users who decline Open Access still get a working product.
- **What leaves the device?** By default, nothing. If the user enables remote LLM processing (off by default), only post-recognition text is sent, audio is never sent, and the active mode is shown in the UI.
- **Privacy nutrition label:** drafted in Phase 0, finalized in Phase 6. Categories: Microphone (linked to user), Audio Data (not collected), User Content text (linked to user, processed locally only unless remote LLM is enabled).

---

## Implementation Phases

### Phase 0 — Foundation, Spikes, and Privacy Narrative

Goal: validate the architecture and resolve every blocking decision before Phase 1 starts.

Scaffold hardening (immediate, low-risk):

- Add `.entitlements` files to both targets with `com.apple.security.application-groups = ["group.com.voiceflow.shared"]`.
- Set `RequestsOpenAccess = true` in [`VoiceFlow/VoiceFlowKeyboard/Info.plist`](VoiceFlow/VoiceFlowKeyboard/Info.plist) (so the user *can* grant it; the app still works without).
- Confirm deployment target after the min-iOS investigation; current scaffold reads `26.4`, which is unrealistic — drop to the chosen baseline.
- Verify `.gitignore` and README are conflict-free (already done in this round).

Spikes (must produce a written verdict each):

- **In-keyboard recording spike.** Microphone + `SFSpeechRecognizer` running inside the Keyboard Extension on the chosen iOS baseline. Measure peak memory, latency, and stability over 5 min of repeated 10 s dictations. Verdict: primary flow viable / not viable / device-class dependent.
- **Open Access spike.** Confirm `openURL` from the extension and microphone-in-extension behavior with and without Open Access. Verdict: feature matrix.
- **App Group store spike.** Implement `SharedStoreClient` with the generation-counter protocol; verify cross-process consistency under contention.
- **Insert spike.** Insert into Notes, Mail, Messages, Safari, plus a known masked field (e.g., a credit-card field).
- **Context spike.** Read context before/after cursor; verify auto-capitalization and spacing logic.
- **Audio spike.** Test interruptions (call, Siri, Focus, headphone unplug) for both flows.
- **Speech spike.** Apple Speech in German, English, and mixed; on-device availability per locale.
- **Min-iOS investigation.** One-page comparison of iOS 17 / 18 / 26 covering Speech APIs, on-device support, SwiftData stability, audio session APIs, Keyboard Extension capabilities. Pick the lowest version that yields meaningful simplicity.
- **Crash reporting spike.** Decide MetricKit vs. third-party.

Documents (must be drafted):

- Privacy nutrition label draft.
- App Review narrative draft.
- Onboarding copy draft (Flow A wording, Open Access trade-off explanation).

Acceptance criteria:

- Primary-flow viability decided with evidence.
- Open Access posture re-confirmed (default: optional with fallback) or revised.
- Min-iOS version decided.
- All nine former *Open Decisions* (now resolved in this document) verified against spike results.
- App Group entitlements wired and verified end-to-end.
- Privacy narrative + onboarding copy written.

### Phase 1 — Keyboard MVP with Secure-Field Handling

Goal: complete dictation loop end-to-end on **both** flows, plus mandatory edge-case handling.

- Keyboard UI states:
  - **Compact** — large mic button, Insert button (when `PendingInsert` exists), Next-Keyboard (globe).
  - **Recording / Transcribing / Reviewing** — primary flow only.
  - **Pending** — preview snippet + Insert + Discard.
- Primary flow end-to-end (gated on Open Access).
- Fallback flow end-to-end (no Open Access). Includes "Switch back to <target app>" copy in the containing app after writing `PendingInsert`.
- `SharedStoreClient` honors the generation-counter protocol.
- Rule-based postprocessing (in-extension and in-app, sharing the framework).
- Manual insert through Keyboard Extension.
- **Secure Field / Phone Pad / disabled-keyboard detection with clipboard fallback.** Pulled forward from old Phase 4.
- All performance budgets met on a representative device (iPhone 12 or newer).
- Onboarding screen with keyboard activation, permissions, and Open Access trade-off explanation.
- Accessibility baseline (VoiceOver labels, 44×44 hit targets, Dynamic Type up to XXXL).
- Telemetry: MetricKit reports surfaced in Settings.

Acceptance: a user, in another app, can switch to VoiceFlow Keyboard, dictate, format, and insert text into the focused field — on **both** flows — and gets a clean fallback in unsupported fields.

### Phase 2 — Postprocessing, Vocabulary, Accessibility hardening

Goal: text quality is visibly better than raw recognition output, and the keyboard is usable by users relying on assistive tech.

- `PostProcessor` with correction levels (minimal / soft / medium).
- LLM adapter as an exchangeable service; default to local-only / off for MVP.
- Hallucination guardrails (word-count deviation, similarity ratio, repetition filter).
- Vocabulary learning from raw vs. corrected text.
- Vocabulary UI in the containing app (show, edit, delete, disable).
- Accuracy ratio stored per dictation.
- VoiceOver user can complete primary flow without sighted assistance — exit criterion.
- Localization for German + English UI strings finalized.

Acceptance: domain terms reliably corrected; LLM never freely adds content or rewrites meaning; VoiceOver flow passes.

### Phase 3 — History, Analytics, Reuse

Goal: dictations are searchable and reusable.

- History with search.
- Insert latest dictation directly from keyboard.
- Favorites/snippets in keyboard (memory-budget aware).
- Analytics (local only): words today, words 7d, total words, WPM, streak, longest text, average session.
- App Shortcuts: start new dictation, copy latest dictation, share latest dictation.
- Localization completeness audit.

Acceptance: user finds old dictations, re-inserts them, understands their usage history.

### Phase 4 — Robustness, Edge Cases, Performance Budgets

Goal: every iOS edge case is handled cleanly; performance budgets validated on the lowest-supported device.

- Full *Insert Edge Cases* list addressed (marked text, RTL, undo grouping, masked fields, predictive overrides).
- Improve insert context: leading space, sentence start, paragraph start, selection replacement where allowed.
- Harden App Group sync under poor conditions (low memory, fast app switching).
- Re-measure all performance budgets on the lowest-supported device class. Fix or document deviations.
- Landscape and small-display layouts.
- RTL hardening (no crashes, correct logical-order insertion).

Acceptance: no silent failures in iOS edge cases; all numeric budgets met on minimum-supported hardware.

### Phase 5 — Optional Offline ASR (gated by proven need)

Goal: build custom speech recognition only if Apple Speech is provably insufficient.

- Evaluate Whisper/Core ML or whisper.cpp/Metal.
- Test tiny / base / small model sizes.
- Evaluate batch vs. streaming.
- Measure battery, memory, thermal load, latency.
- Compare quality against Apple Speech.
- Define "fully local" privacy mode.

Acceptance: custom ASR ships only if it provides a clear, measured advantage over Apple Speech for a defined user segment.

### Phase 6 — Release Readiness

Goal: App Store ready.

- Active engine display (Apple Speech / Apple On-Device / local Whisper / LLM mode).
- Permission copy finalized for microphone and Speech Recognition.
- Data deletion for history and vocabulary.
- Export / backup for history and vocabulary.
- Privacy text for Keyboard Extension and Open Access finalized.
- Privacy nutrition label finalized.
- App Review narrative finalized.
- fastlane release pipeline.

Acceptance: stable permission and privacy story; user understands which data is processed where.

---

## Recommended Sequence

1. **Phase 0** — Foundation, spikes, privacy narrative
2. **Phase 1** — Keyboard MVP + Secure-Field handling (both flows)
3. **Phase 2** — Postprocessing, vocabulary, accessibility hardening
4. **Phase 3** — History, analytics, reuse
5. **Phase 4** — Robustness, edge cases, perf budgets validated on min-spec hardware
6. **Phase 5** — Offline ASR (only with proven need)
7. **Phase 6** — Release readiness

---

## Resolved Decisions (formerly "Open Decisions")

| Question | Resolution | Where decided |
| --- | --- | --- |
| How does the user return to the target app after recording? | Primary flow eliminates the return trip; fallback flow uses the iOS breadcrumb / App Switcher with explicit "Switch back to <app>" copy. | Architectural Reframe |
| Should Phase 1 attempt auto-insert or require explicit "Insert"? | Manual Insert in MVP. Auto-insert is post-MVP. | MVP Scope → Not In MVP |
| Does the Keyboard Extension need `RequestsOpenAccess`? | `RequestsOpenAccess = true` in Info.plist so users *can* grant it. The MVP works without via the fallback flow. | Open Access decision policy + Phase 0 |
| Which App Group store is most robust? | `UserDefaults(suiteName:)` for `PendingInsert` and small state; SwiftData or shared SQLite for history and vocabulary. Generation-counter protocol mandatory. | App Group Storage Strategy + App Group Concurrency Protocol |
| Is the MVP LLM local, remote, or only an interface? | MVP: only an interface plus local rules. Remote LLM is gated on a separate explicit privacy review (post-MVP). | MVP Scope → Not In MVP |
| What minimum iOS version? | Decided in Phase 0 (min-iOS investigation). Default baseline iOS 17 unless investigation finds a specific simplification at a higher version. | Phase 0 |
| Which launch languages are mandatory? | German and English; mixed German/English dictation supported. | Localization |
| Should audio be temporarily storable for debugging? | Off by default; opt-in only, never persisted by default. | Privacy Rules |
| How large may keyboard history be inside the extension? | Last 5 entries loaded eagerly; full history accessed only via the containing app. | Memory Budget |
| Should the keyboard show only VoiceFlow functions or also basic keys? | MVP: VoiceFlow functions + Next-Keyboard (globe). A full character keyboard is post-MVP. | MVP Scope → Not In MVP |

---

## Test Plan

### Phase 0 Tests

- Insert in Apple Notes, Mail, Messages, Safari.
- Behavior in Secure Field and Phone Pad.
- Behavior after Extension restart (cold).
- Behavior without App Group access (entitlement misconfigured).
- Apple Speech in German, English, and mixed.
- In-keyboard recording on iPhone 12 / 14 / 15 / 16 (or chosen device set) — memory + latency.
- App Group concurrency under contention (interleaved writes).

### MVP Acceptance Tests

- Start dictation from target app — primary flow.
- Start dictation from target app — fallback flow.
- Cancel recording; confirm recording.
- Edit raw text before save.
- Insert final text.
- Reinsert latest dictation.
- Use clipboard fallback in unsupported field.
- Deny permission then grant later.
- Simulate speech unavailable (offline + locale not on-device).
- Simulate corrupted / empty App Group store.
- VoiceOver complete primary flow end-to-end.
- Dynamic Type at XXXL — no clipped UI in keyboard.

---

## Known Risks

| Risk | Cause | Mitigation |
| --- | --- | --- |
| In-keyboard recording exceeds extension memory budget | Live audio + recognition + UI in 48 MB | Phase 0 spike measures; primary flow restricted to device classes that pass; otherwise fallback flow used |
| User does not enable Open Access | Privacy concern, friction | Fallback flow ships first-class; onboarding explains trade-off in plain language |
| Apple rejects custom-keyboard + microphone combo | Elevated App Review scrutiny | App Review narrative drafted in Phase 0; clear disclosures |
| User loses context while switching apps (fallback flow) | iOS forbids return-to-app | `PendingInsert` with TTL; primary flow used when possible |
| Keyboard unavailable in some apps | App blocks third-party keyboards | Clipboard fallback + clear UI |
| No insert in Secure Fields | iOS replaces custom keyboard with system keyboard | Detected pre-record in Phase 1; communicate clearly |
| Apple Speech unavailable offline | Locale/device/iOS dependency | Per-locale availability check at runtime; allow online mode or evaluate Whisper later |
| LLM hallucinates formatting | Generative model | Guardrails + fallback to raw text; LLM disabled by default |
| App Group race conditions | Cross-process UserDefaults sync | Generation-counter protocol with consumedGen tombstone |
