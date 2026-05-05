# Phase 0 Spike: App Group Store Contention

> **Verdict:** Viable with a shared file lock plus explicit suite synchronization.
> **Date:** 2026-04-29
> **Status:** Passed for `PendingInsert` generation-counter handoff.

## Question

Can the containing-app and keyboard-extension handoff keep `PendingInsert` consistent when separate app/extension-style processes write, read, and consume the same App Group store under contention?

## Method

Added `AppGroupStoreSpike`, an executable target in `VoiceFlow/VoiceFlowShared`, that launches separate child processes against the same preferences suite and lock file:

- 4 writer processes, alternating `containingApp` and `keyboardExtension` producers.
- 4 keyboard-reader processes calling `pendingInsertForKeyboard()` and occasionally simulating consume.
- 750 writes per writer, 1,500 reads per reader.
- Final invariant: exactly 3,000 monotonic writes, final payload generation equals stored generation, and no reader observes a mixed payload/generation pair.

Command:

```sh
cd VoiceFlow/VoiceFlowShared
swift run AppGroupStoreSpike
```

Passing run:

```text
App Group store contention spike passed
writers: 4, writer iterations: 750
readers: 4, reader iterations: 1500
final generation: 3000
```

## Findings

Raw multi-key `UserDefaults` access was not robust enough under separate macOS processes. The first contention run exposed a mixed read (`payloadGeneration` behind stored `generation`) when one process observed stale preference cache state.

The fix is to treat the generation-counter sequence as a critical section:

- All `PendingInsert` read/write/consume paths take an exclusive App Group file lock.
- Suite-backed clients use `CFPreferences` primitives plus explicit synchronization inside the lock.
- Injected `UserDefaults` remains supported for unit tests.
- Stale consume is expected if a newer generation arrives after the keyboard reads an older pending insert; the client refuses to tombstone the newer generation.

## Verdict

The `PendingInsert` handoff is viable for Phase 1 if all app and keyboard-extension code uses `SharedStoreClient` rather than reading the preference keys directly. Direct raw access to `pendingInsert.payload`, `pendingInsert.generation`, or `pendingInsert.consumedGen` is not allowed because it can reintroduce torn reads or stale-cache races.

This spike only validates `PendingInsert`. SwiftData-backed history and vocabulary still need separate validation when those stores are implemented.
