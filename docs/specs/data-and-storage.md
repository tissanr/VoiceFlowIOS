# Spec: Data & Storage

> **Spec status:** Accepted (v3) — v3 moves history and vocabulary from SwiftData to locked JSON file stores and adds vocabulary status/source fields
> **Implementation status:** In progress (App Group entitlements, shared model package, `PendingInsert` `SharedStoreClient` verified under contention; JSON file stores for vocabulary, history, settings, and keyboard edit watch implemented; real-device App Group validation pending)
> **Last updated:** 2026-11-10
> **Owners:** iOS

Models, the App Group store layout, and the cross-process concurrency protocol that connects the containing app to the Keyboard Extension.

---

## App Group identifiers

| Identifier | Value |
| --- | --- |
| App Group | `group.me.tissanr.VoiceFlow.shared` |
| Containing app bundle ID | `me.tissanr.VoiceFlow` |
| Keyboard extension bundle ID | `me.tissanr.VoiceFlow.VoiceFlowKeyboard` |

The App Group ID must match in both targets' `.entitlements`, in `SharedStoreClient`, and in any code or doc that references it. There is no other App Group ID in this project.

---

## Storage layout

| Data | Storage | Reason |
| --- | --- | --- |
| `PendingInsert`, `KeyboardState`, generation counter | App Group suite preferences via `SharedStoreClient` | `PendingInsert` uses a shared App Group file lock plus explicit suite synchronization; do not access its raw keys directly. |
| `DictationRecord` (history) | `DictationHistoryStore`: `Stores/history.json` in the App Group container, newest first, capped at 100 | Written by both processes; small; whole-file atomic writes survive extension termination. |
| `VocabularyEntry` | `VocabularyStore`: `Stores/vocabulary.json` in the App Group container | Read by the keyboard at dictation start; hundreds of entries at most, so a linear scan is enough. |
| `KeyboardEditWatch` | `KeyboardEditWatchStore`: `Stores/keyboard-edit-watch.json` | Last keyboard insertion, kept so a later post-edit can be learned after iOS terminated the extension. |
| `VoiceFlowSettings` | App Group suite preferences, key `settings.v1` (JSON) via `SettingsStore` | Small, hot, atomic; missing keys decode to defaults. |
| Diagnostic ring buffer | Shared file in the App Group container | Local-only, no network telemetry. |

The Keyboard Extension never opens the heavy store at launch; it only opens App Group suite preferences and lazy-loads the items it needs (last 5 history entries, vocabulary subset). See [performance-and-memory.md](performance-and-memory.md).

The JSON file stores share one helper, `SharedJSONFileStore`: every read and read-modify-write runs under an `flock` on a sibling `.lock` file (the same lock primitive `SharedStoreClient` uses), and writes are atomic file replacements. **v3 change:** the Phase 0 min-iOS investigation ([../spikes/min-ios-investigation.md](../spikes/min-ios-investigation.md)) had selected SwiftData for history and vocabulary. History is capped at 100 records and vocabulary stays in the hundreds, so a locked JSON file is simpler, costs the keyboard no SwiftData stack in its ~48 MB budget, and is unit-testable from the Swift package on macOS. Revisit (SwiftData or shared SQLite) if history needs search or grows past a few hundred KB. The `PendingInsert` contention verdict is documented in [../spikes/app-group-store-contention.md](../spikes/app-group-store-contention.md).

The extension-safe model definitions and `PendingInsert` shared-store client live in the local Swift package at [../../VoiceFlow/VoiceFlowShared](../../VoiceFlow/VoiceFlowShared).

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
    var editedText: String?      // user's correction from History or a detected keyboard post-edit
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
    var heard: String            // empty = plain term (recognition hint only)
    var correction: String
    var isEnabled: Bool
    var createdAt: Date
    var lastUsedAt: Date?
    var useCount: Int
    var status: VocabularyStatus // .suggested | .active | .rejected
    var source: VocabularySource // .manual | .historyEdit | .keyboardEdit
    var timesObserved: Int       // how often a learned pair was seen
}
```

Only `.active` + enabled entries affect recognition and correction. Learned pairs start as `.suggested`; `.rejected` entries are kept so the same pair is not suggested again. Decoding tolerates missing new keys.

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

`PendingInsert` is the most contentious shared object. The protocol below eliminates torn reads despite cross-process suite preferences not being instantaneously consistent.

### Keys

```text
SharedStoreClient(suiteName: "group.me.tissanr.VoiceFlow.shared")

  pendingInsert.payload      // Codable PendingInsert blob
  pendingInsert.generation   // monotonic Int, incremented on every write
  pendingInsert.consumedGen  // generation last consumed by the keyboard
  Locks/pending-insert.lock  // App Group file lock guarding the read/write sequence
```

### Rules

- Only the **producing side** writes `pendingInsert.payload` and bumps `generation`:
  - Primary flow: Keyboard Extension produces.
  - Fallback flow: Containing app produces.
- All producers and consumers must go through `SharedStoreClient`; direct raw key access is prohibited.
- `SharedStoreClient` takes the App Group file lock and synchronizes the suite before reading and after mutating the `PendingInsert` keys.
- The **consuming side** is always the Keyboard Extension at insert time. It only reads when `generation > consumedGen`.
- After successful insert, the keyboard sets `consumedGen = generation` and writes `consumedAt` into the payload.
- TTL: payloads with `createdAt` older than 10 minutes are considered stale and ignored.
- Tombstone on consume; never delete records mid-flight (the user may re-insert from history).

### Failure handling

- If `payload` decode fails: treat as `sharedStoreUnavailable`, surface error in keyboard UI, keep raw text in history if available.
- If the keyboard is terminated mid-insert: `consumedGen` is not bumped; on next launch the keyboard sees `generation > consumedGen` and offers Insert again.
- If a newer generation appears after the keyboard has read an older pending insert, `consumePendingInsert(generation:)` must refuse to tombstone the newer generation.
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
- Concurrent reads from the keyboard during a write from either producer must always see *either* the old payload or the new one, never a mixed state. Validated under contention in [../spikes/app-group-store-contention.md](../spikes/app-group-store-contention.md).
