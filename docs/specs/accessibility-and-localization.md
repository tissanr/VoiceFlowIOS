# Spec: Accessibility & Localization

> **Spec status:** Accepted (v1)
> **Implementation status:** Not started (Phase 2 exit criteria)
> **Last updated:** 2026-04-28
> **Owners:** iOS + product

---

## Accessibility

A voice-first app with an inaccessible keyboard fails its own thesis. These are MVP exit criteria, not Phase 6 polish.

- Every interactive element in the keyboard exposes a **VoiceOver label** and **hint** (e.g., "Microphone, double tap to start dictation").
- Hit targets ≥ **44×44 pt** (Apple HIG).
- **Dynamic Type** up to `.accessibilityExtraExtraExtraLarge` must not break the keyboard layout. Use scrollable / wrapping layouts, not clipping.
- Sufficient **color contrast** (≥ 4.5:1 text, ≥ 3:1 UI) in both light and dark mode.
- **Reduced Motion** respected — no purely decorative animations during dictation.
- A VoiceOver user must be able to complete the **primary flow** end-to-end without sighted assistance — Phase 2 exit criterion.
- Audio cues do not replace visual cues; visual cues do not replace audio cues. Users must be able to dictate while glancing only or listening only (within reason).

### Test matrix

- VoiceOver on/off × primary flow / fallback flow.
- Dynamic Type at `large`, `XXL`, `XXXL`, `accessibilityExtraExtraExtraLarge`.
- Reduced Motion on/off.
- Light mode / Dark mode contrast check.

---

## Localization

### Launch languages

- **German (de)** and **English (en)** for UI strings and dictation.
- **Mixed German / English dictation** is a recognized recurring use case; the speech engine should not be forced into a single locale per session if the user has chosen Auto.

### Implementation rules

- **String catalogs:** `Localizable.xcstrings` (Xcode 15+) for both targets. The keyboard extension and the containing app share a string-keys convention.
- **Per-locale Speech availability** is checked at runtime (`SFSpeechRecognizer.supportedLocales()` + `supportsOnDeviceRecognition`). When on-device is unavailable for the user's locale, the UI announces this clearly — never silently downgrades to network without telling the user.
- **Number / date / unit formatting** uses `Locale.current`.
- **Right-to-left text** must not crash or render incorrectly; correct logical-order insertion. RTL is a Phase 4 hardening target (no Arabic / Hebrew dictation in MVP, but no crashes either).

### Localized copy that is App-Review-sensitive

Permission strings (`NSMicrophoneUsageDescription`, `NSSpeechRecognitionUsageDescription`) and onboarding copy are **App-Review-sensitive**. Changes to these go through the App Review narrative — see [privacy-and-app-review.md](privacy-and-app-review.md). Don't tweak the wording in passing.

---

## Cross-references

- Permission copy and privacy narrative: [privacy-and-app-review.md](privacy-and-app-review.md)
- Insert behavior in RTL contexts: [keyboard-and-insert.md](keyboard-and-insert.md)
