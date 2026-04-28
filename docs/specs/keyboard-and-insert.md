# Spec: Keyboard & Insert

> **Spec status:** Accepted (v1)
> **Implementation status:** Not started (Phase 0 pending)
> **Last updated:** 2026-04-28
> **Owners:** iOS

Keyboard UI states, insert path, and the boring edge cases that break custom keyboards.

---

## Keyboard UI states

- **Compact** — default. Large mic button, Insert button (when `PendingInsert` exists), Next-Keyboard (globe).
- **Recording / Transcribing / Reviewing** — primary flow only. Visible level meter, timer, Cancel.
- **Pending** — preview snippet + Insert + Discard.
- **InsertUnavailable** — explains the reason (Secure Field, Phone Pad, store missing, Open Access required) and offers clipboard fallback where applicable.

The Next-Keyboard globe is mandatory per Apple HIG; it must be reachable in every keyboard state.

---

## Insert path

The only primary insert path is `UITextDocumentProxy.insertText(...)`.

### Before insert

- Read `documentContextBeforeInput` and `documentContextAfterInput`.
- Detect sentence start (empty context, or context ending in `.`, `!`, `?`, `:`, or newline).
- Add a leading single space if the context ends without whitespace and the cursor is mid-sentence; never two.
- Avoid duplicate punctuation if the surrounding text already has terminal punctuation.

### After insert

- Set `PendingInsert.consumedAt` and `pendingInsert.consumedGen` (see [data-and-storage.md](data-and-storage.md)).
- Set `DictationRecord.insertedAt`.
- Set keyboard UI to **Inserted**.
- **Verify the insert took:** re-read `documentContextBeforeInput`. If unchanged, the field rejected the insert silently — fall back to clipboard with explanation.

### Fallback (clipboard)

If the keyboard is unavailable, the field rejects insert silently, or `InsertGuard` flags the field as unsupported:

- Copy text to `UIPasteboard`.
- Briefly explain why clipboard was used.
- Never discard text silently.

---

## Insert edge cases (must-handle)

`UITextDocumentProxy.insertText` is not a panacea. The MVP must address:

- **Marked text / IME composition.** If a marked-text composition is in flight (CJK input, autocorrect candidate), clear or commit before inserting.
- **RTL text.** Insert as logical-order text; never reverse for display.
- **Selection replacement.** When the user has a selection, `insertText` replaces it on most fields, but not all. Document and test.
- **Undo grouping.** Insert as a single undoable transaction. Avoid multiple `insertText` calls for one logical insert.
- **Predictive text overrides.** Some apps consume input and re-emit something different. Detect via `documentContextBeforeInput` after insert; warn the user if the result is suspicious.
- **Masked / formatted fields** (credit cards, phone formats). Result may be silently dropped or reformatted. Detect by re-reading post-insert; if no change, fall back to clipboard.
- **Leading whitespace.** Single space if needed; never two.
- **Sentence boundaries.** Capitalize first character at sentence start.
- **Trailing punctuation.** No double-up if surrounding context already has terminal punctuation.

---

## InsertGuard — pre-record detection

Before recording starts (primary flow) or before offering Insert (any flow), the keyboard runs `InsertGuard`:

- **Secure Field detection.** `UITextDocumentProxy.documentContextBeforeInput == nil` plus iOS swapping in the system keyboard is the heuristic. If detected: do not record; show explanation; offer clipboard.
- **Phone Pad / number pads.** Detect via `UITextInputTraits.keyboardType` exposed through the proxy where possible. If detected: do not record; show explanation.
- **Apps that disable third-party keyboards.** If the keyboard never receives `viewDidAppear` for the input view, the keyboard surface won't render — outside our control. Onboarding must warn users this is possible.

---

## "Next Keyboard" / globe

- Required by Apple HIG.
- Always visible.
- Long-press behavior follows iOS default (keyboard switcher).
- Implemented via `advanceToNextInputModeAction` (or equivalent on the chosen iOS baseline).

---

## Cross-references

- Where the inserted text comes from: [data-and-storage.md](data-and-storage.md)
- Speech and postprocessing producing the text: [speech-and-postprocessing.md](speech-and-postprocessing.md)
- Memory budget for the keyboard while recording: [performance-and-memory.md](performance-and-memory.md)
- Accessibility requirements for keyboard UI: [accessibility-and-localization.md](accessibility-and-localization.md)
