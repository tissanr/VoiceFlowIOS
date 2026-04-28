# Spec: Data & Storage

> **Spec status:** Accepted (v1)
> **Implementation status:** In progress (App Group entitlements wired; shared models and store pending)
> **Last updated:** 2026-04-28
> **Owners:** iOS

Models, the App Group store layout, and the cross-process concurrency protocol that connects the containing app to the Keyboard Extension.

---

## App Group identifiers

| Identifier | Value |
| --- | --- |
| App Group | `group.com.voiceflow.shared` |
| Containing app bundle ID | `me.tissanr.VoiceFlow` |
| Keyboard extension bundle ID | `me.tissanr.VoiceFlow.VoiceFlowKeyboard` |

The App Group ID must match in both targets' `.entitlements`, in `SharedStoreClient`, and in any code or doc that references it. There is no other App Group ID in this project.

---

## Storage layout

| Data | Storage | Reason |
| --- | --- | --- |
| `PendingInsert`, `KeyboardState`, generation counter | `UserDefaults(suiteName: "group.com.voiceflow.shared")` | Atomic per-key, suitable for extension/app handoffs. |
| `DictationRecord` (history) | SwiftData *or* shared SQLite in the App Group container | Higher volume; choice deferred to Phase 0 min-iOS investigation. |
| `VocabularyEntry` | Same store as `DictationRecord` | Indexed lookup needed for postprocessing. |
| `VoiceFlowSettings` | UserDefaults (subset readable from extension) | Small, hot, atomic. |
| Diagnostic ring buffer | Shared file in the App Group container | Local-only, no network telemetry. |

The Keyboard Extension never opens the heavy store at launch; it only opens UserDefaults and lazy-loads the items it needs (last 5 history entries, vocabulary subset). See [performance-and-memory.md](performance-and-memory.md).

---

## State model

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

enum KeyboardState {
    case noSharedAccess
    case ready
    case recording                   // primary flow only
    case transcribing                // primary flow only
    case hasPendingInsert(DictationID)
    case inserting
    case insertUnavailable(reason: InsertUnavailableReason)
}

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

## Data model

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
    var expiresAt: Date          // 10-minute TTL
    let generation: Int          // matches pendingInsert.generation key
    let producedBy: ProducerSide // .keyboardExtension or .containingApp
}

enum ProducerSide: String, Codable {
    case keyboardExtension
    case containingApp
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

## App Group concurrency protocol

`PendingInsert` is the most contentious shared object. The protocol below eliminates torn reads despite cross-process `UserDefaults` not being instantaneously consistent.

### Keys

```text
UserDefaults(suiteName: "group.com.voiceflow.shared")

  pendingInsert.payload      // Codable PendingInsert blob
  pendingInsert.generation   // monotonic Int, incremented on every write
  pendingInsert.consumedGen  // generation last consumed by the keyboard
```

### Rules

- Only the **producing side** writes `pendingInsert.payload` and bumps `generation`:
  - Primary flow: Keyboard Extension produces.
  - Fallback flow: Containing app produces.
- The **consuming side** is always the Keyboard Extension at insert time. It only reads when `generation > consumedGen`.
- After successful insert, the keyboard sets `consumedGen = generation` and writes `consumedAt` into the payload.
- TTL: payloads with `createdAt` older than 10 minutes are considered stale and ignored.
- Tombstone on consume; never delete records mid-flight (the user may re-insert from history).

### Failure handling

- If `payload` decode fails: treat as `sharedStoreUnavailable`, surface error in keyboard UI, keep raw text in history if available.
- If the keyboard is terminated mid-insert: `consumedGen` is not bumped; on next launch the keyboard sees `generation > consumedGen` and offers Insert again.
- If the App Group is misconfigured (entitlement missing): keyboard enters `KeyboardState.noSharedAccess` and shows a setup hint.

---

## Shared store contract

### Writers

- Primary flow: Keyboard Extension writes `PendingInsert` (with `producedBy = .keyboardExtension`).
- Fallback flow: Containing app writes `PendingInsert` (with `producedBy = .containingApp`).
- Containing app writes `DictationRecord`, settings, and vocabulary at any time.

### Readers

- Keyboard Extension reads `PendingInsert`, reduced settings, and a vocabulary subset.
- Containing app reads anything.

### Rules

- The concurrency protocol (generation counter, `consumedGen` tombstone) is mandatory.
- Keyboard Extension must not trigger long write operations; lazy-load only what's needed.
- Store access must be fault-tolerant — extensions can be terminated at any time.
- TTL on `PendingInsert` is 10 minutes; older payloads are ignored.

---

## Test invariants

- `generation` is strictly monotonic across both producers; attempts to write a non-increasing generation must fail loudly in debug builds.
- A `PendingInsert` past `expiresAt` must never be inserted, even if `generation > consumedGen`.
- Concurrent reads from the keyboard during a write from either producer must always see *either* the old payload or the new one, never a mixed state. Validated under contention in the Phase 0 spike.
