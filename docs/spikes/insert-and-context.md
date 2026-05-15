# Phase 0 Spike: Insert and Context

> **Date:** 2026-05-15
> **Status:** In progress
> **Scope:** Insert-context planning rules, host-app insertion checklist, and remaining manual validation gaps.

## Question

Can VoiceFlow prepare dictated text for `UITextDocumentProxy.insertText(...)` without introducing obvious spacing, capitalization, or duplicate-punctuation errors, and what still needs manual host-app validation before Phase 1 sign-off?

## Automated result

The pure context-planning rules are implemented in `VoiceFlowShared` as `InsertContextPlanner` and covered by unit tests.

Covered by `swift test`:

- Adds one leading space when inserting in the middle of a sentence.
- Avoids a duplicate leading space when the existing context already ends with whitespace.
- Capitalizes the first letter at empty context, after terminal punctuation, and after a newline.
- Treats `.`, `!`, `?`, `:`, and newline as sentence boundaries.
- Removes duplicate terminal punctuation when the inserted text ends with punctuation and the following context already starts with terminal punctuation.
- Avoids adding a leading space before punctuation-led inserts.
- Trims dictation text before planning.

## Verdict

Context planning is viable for Phase 1 as shared, extension-safe logic. The keyboard should call the planner once, then perform a single `insertText(...)` call with the planned string so the insert remains one logical undo transaction.

This spike does **not** prove that every host app accepts or preserves inserted text. Real insertion validation remains required before the insert spike is complete.

## Manual host-app validation still required

Run the keyboard against these targets and record the observed behavior:

| Target | Required observation |
| --- | --- |
| Notes | Plain text insert, sentence start, middle-of-sentence spacing, post-insert context changed. |
| Mail | Body-field insert, new paragraph behavior, post-insert context changed. |
| Messages | Composer insert, predictive text interaction, post-insert context changed. |
| Safari | Web text field and textarea insert, post-insert context changed. |
| Masked field | Known credit-card / phone-style field either accepts, reformats, or rejects text; rejection falls back to clipboard. |
| Secure Field | Third-party keyboard unavailable or context is inaccessible; do not record or silently discard text. |
| Phone Pad / number pad | Unsupported keyboard type is detected where possible; do not offer normal dictation insert. |

## Phase 1 implementation notes

- `KeyboardViewController` should read `documentContextBeforeInput` and `documentContextAfterInput` immediately before insert.
- If `InsertGuard` reports an unsupported field, skip `insertText(...)` and use the clipboard fallback.
- After `insertText(...)`, re-read `documentContextBeforeInput`; if unchanged or suspicious, preserve the text and show the clipboard fallback.
- On confirmed insert, mark the matching `PendingInsert` generation consumed through `SharedStoreClient`.

## Verification

Command:

```sh
swift test
```

Result on 2026-05-15: passed from `VoiceFlow/VoiceFlowShared`.
