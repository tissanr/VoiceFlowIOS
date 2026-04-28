# VoiceFlow iOS - Roadmap & Product Specification

> **Last updated:** 2026-04-28
> **Purpose:** iOS product specification for VoiceFlow as a keyboard-centered dictation and text-formatting app

---

## Product Goal

VoiceFlow iOS should let users dictate text while working in other iOS apps, improve the recognized raw transcript, and insert the final text into the currently selected text field.

The clean iOS architecture is:

```text
VoiceFlow Keyboard Extension
  + VoiceFlow Containing App
  + Apple Speech / optional offline engine later
  + LLM/rule-based postprocessing
  + App Group store for result handoff
```

VoiceFlow does not replace Apple's system dictation. VoiceFlow is enabled as a custom keyboard and writes into the active text field through the official keyboard APIs.

---

## iOS Assumptions

### What iOS Allows

- A Custom Keyboard Extension can be enabled systemwide as a keyboard.
- When VoiceFlow is the active keyboard, it can insert text into the currently selected text field using `UITextDocumentProxy.insertText(...)`.
- The Keyboard Extension can read limited context around the cursor:
  - `documentContextBeforeInput`
  - `documentContextAfterInput`
- The containing app can handle microphone recording, speech recognition, LLM formatting, history, vocabulary, and settings.
- The containing app and Keyboard Extension can exchange data through App Groups.

### What iOS Does Not Allow

- No global push-to-talk hotkey.
- No systemwide simulation of keyboard input into arbitrary apps.
- No registration as a replacement provider for Apple's system dictation service.
- No interception of normal Apple dictation output before insertion.
- No reliable microphone/speech workflow directly inside a Keyboard Extension.
- No availability in every field: Secure Fields, Phone Pads, and apps that disable third-party keyboards can exclude VoiceFlow.
- **No programmatic "Return to App":** iOS does not allow the app to force the user back to the previous application. The user must use the system "Back" breadcrumb or the App Switcher.

---

## Technical Refinements & Constraints

### Open Access (Full Access) Requirement
- **Deep Linking:** Opening the containing app from the keyboard via `openURL` typically requires the user to enable "Allow Full Access" in iOS Settings.
- **App Group Latency:** While App Groups work without Full Access, some synchronization edge cases are smoother with it.
- **Decision:** Phase 0 must confirm if the MVP will mandate "Full Access" or if a fallback (instructional UI) is preferred.

### App Group Storage Strategy
- **Low Latency (`PendingInsert`, `KeyboardState`):** Use `UserDefaults(suiteName: "group.com.voiceflow")`. This is atomic and highly reliable for extension-to-app handoffs.
- **High Volume (`DictationRecord`, `VocabularyEntry`):** Use `SwiftData` or a shared SQLite file.
- **Group ID:** `group.com.voiceflow.shared` (to be configured in Entitlements).

### Audio Session Management
- **Category:** `.playAndRecord` or `.record`.
- **Options:** `.allowBluetooth`, `.duckOthers`, and `.interruptSpokenAudioAndMixWithOthers` to ensure the app doesn't abruptly kill the user's background music/podcasts unless necessary.

---

## Microphone Button Below The Keyboard

The microphone button below the iOS keyboard belongs to Apple's system dictation. VoiceFlow cannot register itself there as an alternative provider.

`UIInputViewController.hasDictationKey` does not mean that VoiceFlow can replace Apple's dictation button. It only controls whether a Custom Keyboard Extension presents its own dictation key in its UI, so iOS does not also show a confusing system dictation button.

Consequence:

- VoiceFlow shows its own microphone button inside the VoiceFlow keyboard.
- This button starts the VoiceFlow dictation flow.
- Recording happens in the containing app, not in the Keyboard Extension.
- The final result is written to the App Group store.
- After returning to the target app, the Keyboard Extension inserts the text using `UITextDocumentProxy.insertText(...)`.

---

## Target Workflow

```text
User is in Notes, Mail, Messages, Safari, etc.
  -> User focuses a text field
  -> User switches to the VoiceFlow keyboard
  -> User taps the VoiceFlow microphone button
  -> VoiceFlow containing app records audio
  -> Apple Speech produces raw text
  -> LLM/rules format the text
  -> Result is saved to the App Group store
  -> User returns to the target app
  -> Keyboard Extension inserts the result into the active text field
```

MVP variant:

- After recording, the containing app briefly shows the result.
- User can confirm or cancel.
- Keyboard Extension then offers "Insert Last Dictation".

Later variant:

- Auto-insert once the user returns to the target app / Keyboard Extension.
- Optional quick confirmation inside the keyboard UI.

---

## MVP Scope

### Must Have

- VoiceFlow Keyboard Extension can insert text into supported text fields.
- Containing app can request microphone and speech-recognition permissions.
- Containing app can record a dictation and transcribe it with Apple Speech.
- Containing app can normalize the raw text with rule-based postprocessing.
- Containing app writes the final text to an App Group store.
- Keyboard Extension reads the latest final text from the App Group store.
- Keyboard Extension inserts the text using `UITextDocumentProxy.insertText(...)`.
- Error states are shown visibly and are not silently ignored.

### Should Have

- Simple history list in the containing app.
- Manual editing of the final text before saving.
- Context-aware capitalization using `documentContextBeforeInput`.
- Clipboard fallback when insert is not possible.
- Language setting for German / English / Auto, if Apple Speech supports the target setup well enough.

### Not In MVP

- Custom Whisper/Core ML ASR.
- Fully local LLM.
- Automatic insert without user confirmation.
- Advanced analytics.
- iCloud sync.
- Full custom keyboard with all standard keys as a replacement for Apple's keyboard.

---

## User Flows

### Flow A - First Setup

```text
User opens VoiceFlow app
  -> App explains keyboard setup and privacy
  -> User enables VoiceFlow Keyboard in iOS Settings
  -> User grants microphone permission
  -> User grants speech-recognition permission
  -> App runs a test dictation
  -> App shows: "Keyboard ready"
```

Acceptance criterion:

- User can understand why keyboard, microphone, and speech-recognition permissions are needed without technical jargon.

### Flow B - Dictation From Another App

```text
User focuses a text field in the target app
  -> User switches to VoiceFlow Keyboard
  -> User taps microphone button
  -> Keyboard opens VoiceFlow app via deep link
  -> App starts recording
  -> User stops recording
  -> App transcribes and formats
  -> User confirms result
  -> App saves result as pendingInsert
  -> User returns to target app
  -> VoiceFlow Keyboard shows pendingInsert
  -> User taps Insert
  -> Keyboard inserts text and marks pendingInsert as consumed
```

Acceptance criterion:

- No recognized text is lost, even if the user switches between apps or the keyboard extension reloads.

### Flow C - Reinsert Latest Dictation

```text
User opens VoiceFlow Keyboard
  -> Keyboard shows latest dictation
  -> User taps Insert
  -> Text is inserted into the active field
```

Acceptance criterion:

- The flow works without a new recording.

### Flow D - Unsupported Field

```text
User is in Secure Field / Phone Pad / app without third-party keyboards
  -> VoiceFlow Keyboard is unavailable or insert fails
  -> Containing app can place result on clipboard
  -> UI briefly explains the reason
```

Acceptance criterion:

- User gets a clear fallback and no technical error message.

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
    case unknown
}
```

---

## Target Architecture

```text
VoiceFlowApp
  -> RecordingController
       AVAudioSession / AVAudioEngine
  -> SpeechEngine
       AppleSpeechEngine first
       WhisperEngine optional later
  -> PostProcessor
       rules + optional LLM
  -> VocabularyStore
       domain terms, correction pairs
  -> DictationStore
       latest text, history, status
  -> SettingsStore
       language, correction level, privacy mode

VoiceFlowKeyboardExtension
  -> KeyboardViewController
       microphone button, Insert, Retry, Cancel
  -> TextProxyWriter
       UITextDocumentProxy.insertText(...)
  -> CursorContextReader
       documentContextBeforeInput / AfterInput
  -> SharedStoreClient
       reads App Group store
```

Shared code should live in an extension-safe framework. Code that uses the microphone, speech recognition, or APIs unavailable to extensions stays exclusively in the containing app.

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
    var expiresAt: Date // Recommendation: 5-10 minute TTL for stale dictations
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

The App Group store is the central interface between the containing app and the Keyboard Extension. It must remain small, robust, and low-transaction.

### Writer

- Containing app writes `PendingInsert`.
- Containing app writes `DictationRecord`.
- Containing app writes settings and vocabulary.

### Reader

- Keyboard Extension reads `PendingInsert`.
- Keyboard Extension reads reduced settings.
- Keyboard Extension reads favorites/snippets.

### Rules

- Keyboard Extension must not trigger long write operations.
- `PendingInsert` remains available until insert succeeds or the user discards it.
- After successful insert, the Keyboard Extension sets `consumedAt`.
- Store access must be font-tolerant because extensions can be terminated at any time.

---

## Core Technologies

| Area                       | Technology                                                 |
| -------------------------- | ---------------------------------------------------------- |
| App UI                     | SwiftUI                                                    |
| Keyboard Extension         | `UIInputViewController`, UIKit                             |
| Text insertion             | `UITextDocumentProxy.insertText(...)`                      |
| Cursor context             | `documentContextBeforeInput`, `documentContextAfterInput`  |
| Audio recording            | `AVAudioSession`, `AVAudioEngine`                          |
| Speech recognition MVP     | `SFSpeechRecognizer`                                       |
| On-device speech check     | `supportsOnDeviceRecognition`                              |
| Postprocessing             | Rule pipeline + optional local LLM adapter                 |
| Persistence                | SwiftData or SQLite                                        |
| Extension communication    | App Groups, shared container, UserDefaults/file/SQLite     |
| Shortcuts                  | App Intents                                                |
| Later offline ASR          | Whisper/Core ML or whisper.cpp/Metal                       |

---

## Speech Strategy

Custom voice recognition is not required for the MVP. VoiceFlow should first use Apple's Speech framework, but not Apple's ready-made system dictation button.

The distinction is central:

- **Not possible:** Replace Apple's dictation button or intercept its output.
- **Possible:** Start a VoiceFlow-owned recording and produce raw text through `SFSpeechRecognizer`.

### Decision

Apple Speech is the first `SpeechEngine`. Whisper/Core ML remains a later alternative if Apple Speech is insufficient for quality, offline availability, mixed-language dictation, or privacy.

```swift
protocol SpeechEngine {
    func requestPermissions() async throws
    func start(locale: Locale) async throws
    func stop() async throws -> SpeechResult
}
```

| Option                         | Benefit                                                     | Drawback                                                              | Decision                              |
| ------------------------------ | ----------------------------------------------------------- | --------------------------------------------------------------------- | ------------------------------------- |
| Apple Speech Framework         | Fast MVP, native API, low ML complexity                     | Own recording required, system behavior not fully controllable         | MVP default                           |
| Apple Speech On-Device         | Potentially local without a custom model                    | Availability depends on language/device/iOS version                    | Validate in Phase 0                   |
| Whisper/Core ML                | Full control, consistent offline story                      | Model size, battery, memory, latency, conversion work                  | Later, only with proven need          |

---

## Postprocessing Strategy

VoiceFlow differentiates primarily through text quality after recognition, not through speech recognition itself.

### Responsibilities

- Normalize punctuation and whitespace.
- Capitalize sentence starts.
- Correct domain terms and proper nouns.
- Handle mixed German/English dictation better.
- Preserve spoken style; do not freely rewrite content.
- Optionally offer formatting profiles:
  - minimal: obvious mistakes only
  - soft: punctuation, capitalization, light grammar
  - medium: improve readability while preserving content

### Guardrails

- Maximum word-count deviation.
- Length limit.
- Similarity ratio between raw text and correction.
- Repetition filter.
- Fallback to raw text when correction is uncertain.

### Vocabulary

Apple Speech cannot be controlled with a free-form `initial_prompt` like Whisper. Vocabulary is therefore applied after the speech result:

```text
Speech raw text
  -> apply known correction pairs
  -> format with LLM/rules
  -> learn new correction pairs
```

---

## Insert Strategy

The only primary insert path is `UITextDocumentProxy.insertText(...)`.

### Before Insert

- Read `documentContextBeforeInput`.
- Detect sentence start.
- Add a leading space depending on context if no whitespace is present.
- Avoid duplicate punctuation if the text already ends with punctuation.

### After Insert

- Set `PendingInsert.consumedAt`.
- Set `DictationRecord.insertedAt`.
- Set keyboard UI to "Inserted".

### Fallback

If the keyboard is unavailable or insert appears impossible:

- Copy text to `UIPasteboard`.
- Briefly explain why clipboard was used.
- Never discard text silently.

---

## Permissions And Privacy

### Required Permissions

- Microphone: for recording in the containing app.
- Speech Recognition: for `SFSpeechRecognizer`.
- Optional Keyboard Open Access: only if strictly required for App Group access, network access, or an expanded shared store.

### Privacy Rules

- Do not store audio in the MVP except for explicit debugging.
- Raw text and final text remain local unless an external LLM mode is enabled.
- If an external LLM is used, the mode must be clearly visible and disableable.
- Keyboard Extension should only read the data needed for insert/favorites.
- Secure Fields are not bypassed.

---

## Implementation Phases

### Phase 0 - Technical Spike

Goal: Validate iOS limits early.

- **Configure App Group:** Set up `group.com.voiceflow.shared` entitlements.
- **Shared Data Spike:** Implement a `SharedUserDefaults` wrapper and test cross-process value updates.
- **Open Access Test:** Verify if `NSExtensionContext().open(url)` works without Full Access.
- **Insert Spike:** Insert test text through `UITextDocumentProxy.insertText(...)`.
- **Context Spike:** Read context before/after cursor to handle auto-capitalization/spacing.
- **Audio Spike:** Test `AVAudioSession` interruption behavior.
- **Speech Spike:** Basic `SFSpeechRecognizer` loop in the app.
- **Return Trip Spike:** Document the UX of returning to the target app via breadcrumb/switcher.

Acceptance criteria:

- VoiceFlow Keyboard can insert test text in Notes, Mail, Messages, and Safari text fields.
- Containing app can record and transcribe dictations.
- Keyboard Extension can insert the latest dictation from the App Group store.
- Latency for 1-3 sentences is acceptable.
- It is clear whether `RequestsOpenAccess` is needed for the planned store access.

### Phase 1 - Keyboard MVP

Goal: Complete dictation loop from a running target app.

- **Keyboard UI Layout:**
  - **Compact Mode:** Default state. Large Mic button, "Next Keyboard" icon.
  - **Pending Mode:** Shown when `PendingInsert` is active. Preview snippet + "Insert" + "Discard".
  - **Processing Mode:** Visual indicator that app is transcribing.
- Deep link / open-app flow from keyboard to containing app.
- Recording and transcription in the containing app.
- **Return Trip UX:** Add a "Switch back to [App]" button/instruction in the App after recording is finished.
- Rule-based postprocessing (happens in App, never in Extension).
- Result handoff via App Group.
- Manual insert through Keyboard Extension.
- Fallback: copy result to clipboard if keyboard insert is unavailable.
- Minimal history with latest dictation.
- Setup screen with keyboard activation instructions.

Acceptance criterion:

- User can focus a text field in another app, switch to VoiceFlow Keyboard, dictate, format the result, and insert the text into that exact field.

### Phase 2 - LLM Formatting And Vocabulary

Goal: Make VoiceFlow text quality visibly better than raw dictation output.

- `PostProcessor` with correction levels.
- LLM adapter as an exchangeable service.
- Guardrails against hallucinations.
- Vocabulary learning from raw text vs. corrected text.
- Vocabulary UI in the containing app:
  - show
  - edit
  - delete
  - disable
- Store accuracy ratio per dictation.

Acceptance criterion:

- Recurring domain terms are reliably corrected after the speech result.
- LLM corrections must not freely add content or rewrite meaning.

### Phase 3 - History, Analytics, Reuse

Goal: Make dictations searchable and reusable.

- History with search.
- Insert latest dictation directly from keyboard.
- Favorites/snippets in keyboard.
- Analytics:
  - words today
  - words over 7 days
  - total words
  - WPM
  - streak
  - longest text
  - average session duration
- App Shortcuts:
  - start new dictation
  - copy latest dictation
  - share latest dictation

Acceptance criterion:

- User can find old dictations, insert them again, and understand usage history.

### Phase 4 - Keyboard Robustness And System Limits

Goal: Handle iOS edge cases cleanly.

- Detect and explain Secure Fields.
- Detect and explain Phone Pads.
- Handle apps that disable third-party keyboards.
- Cover unsupported text fields with clipboard fallback.
- Optimize keyboard UI for small displays and landscape.
- Harden App Group synchronization.
- Show clear error states:
  - missing permission
  - speech unavailable
  - no latest dictation
  - insert unavailable
- Improve insert context:
  - leading space
  - sentence start
  - paragraph start
  - selection/replacement where `UITextDocumentProxy` allows it

Acceptance criterion:

- The app does not fail silently in iOS edge cases and offers a clear fallback.

### Phase 5 - Optional Offline ASR

Goal: Build custom speech recognition only if need is proven.

- Evaluate Whisper/Core ML or whisper.cpp/Metal.
- Test tiny/base/small model sizes.
- Evaluate batch vs. streaming.
- Measure battery, memory, thermal load, and latency.
- Compare quality against Apple Speech.
- Define "fully local" privacy mode.

Acceptance criterion:

- Custom ASR is integrated only if it provides a clear advantage over Apple Speech.

### Phase 6 - Privacy, Export, Release Readiness

Goal: App Store-ready and trustworthy product line.

- Clear display of active engine:
  - Apple Speech
  - Apple On-Device Speech
  - local Whisper engine
  - LLM local/on/off
- Permission copy for microphone and Speech Recognition.
- Data deletion for history and vocabulary.
- Export/backup for history and vocabulary.
- Privacy text for Keyboard Extension and Open Access.
- Performance budget:
  - app launch
  - recording start
  - transcription latency
  - memory
  - battery

Acceptance criterion:

- User understands which data is processed where.
- The app has a stable permission and privacy story for App Review.

---

## Recommended Sequence

1. Phase 0: Keyboard and Apple Speech spike
2. Phase 1: Keyboard MVP with insert into the running app
3. Phase 2: LLM formatting and vocabulary
4. Phase 3: History, analytics, reuse
5. Phase 4: Keyboard robustness and iOS edge cases
6. Phase 5: Offline ASR only with proven need
7. Phase 6: Privacy, export, release readiness

---

## Open Decisions

- How exactly does the user return to the target app after recording?
- Should Phase 1 attempt auto-insert or require explicit manual "Insert"?
- Does the Keyboard Extension need `RequestsOpenAccess`?
- Which App Group store is most robust: SQLite, file, or UserDefaults?
- Is the MVP LLM local, remote, or initially only an interface?
- What minimum iOS version should be required?
- Which launch languages are mandatory: German, English, mixed German/English?
- Should audio be temporarily storable for debugging, or strictly never persisted?
- How large may keyboard history be inside the extension?
- Should the keyboard show only VoiceFlow functions or also provide basic keys?

---

## Test Plan

### Phase 0 Tests

- Insert in Apple Notes.
- Insert in Mail.
- Insert in Messages.
- Insert in Safari text field.
- Behavior in Secure Field.
- Behavior in Phone Pad.
- Behavior after Extension restart.
- Behavior without App Group access.
- Apple Speech with German.
- Apple Speech with English.
- Apple Speech with mixed German/English.

### MVP Acceptance Tests

- Start dictation from target app.
- Cancel recording.
- Confirm recording.
- Edit raw text.
- Insert final text.
- Reinsert latest dictation.
- Use clipboard fallback.
- Deny permission and grant later.
- Simulate speech unavailable.
- Simulate corrupted/empty store.

---

## Known Risks

| Risk                                         | Cause                                          | Mitigation                                           |
| -------------------------------------------- | ---------------------------------------------- | ---------------------------------------------------- |
| User loses context while switching apps      | Recording runs in containing app               | Store result in App Group, insert after return       |
| Keyboard unavailable in some apps            | App blocks third-party keyboards               | Clipboard fallback and clear UI                      |
| No insert in Secure Fields                   | iOS replaces custom keyboard with system keyboard | Communicate clearly, do not force workaround       |
| Apple Speech unavailable offline             | Language/device/iOS-version dependency         | Allow online mode or evaluate Whisper later          |
| LLM hallucinates formatting                  | Generative model                               | Guardrails and fallback to raw text                  |
| Open Access discourages users                | Keyboard privacy sensitivity                   | Minimal data, clear privacy explanation              |
