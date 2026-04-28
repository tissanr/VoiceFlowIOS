# Agent Guide (shared)

This file is the **single source of truth for AI agents** working in this repo — Codex, Claude Code, and any future tool. Agent-specific files (e.g., [`CLAUDE.md`](CLAUDE.md)) are thin pointers to this document and contain only operational notes that genuinely don't apply to other agents.

The product spec is [`ROADMAP.md`](ROADMAP.md). Read it before making any non-trivial change.

---

## Multi-agent contract

- This file's content stays **agent-neutral**. No "Codex says…" or "Claude says…" instructions in the body. Operational quirks of a specific agent go in that agent's pointer file (e.g., `CLAUDE.md` for Claude Code).
- Any agent that updates this file must keep it agent-neutral and must update the cross-references in the pointer files if section names change.
- If two agents are likely to disagree on a topic (e.g., commit message style), this file decides for the project, not the agent.

---

## Project

VoiceFlow iOS is a keyboard-centered dictation and text-formatting app for iOS. The architecture is dual-flow:

- **Primary flow:** recording, transcription, and postprocessing happen inside the **Keyboard Extension**, gated on user-granted **Open Access**.
- **Fallback flow:** if Open Access is declined, the keyboard hands off to the **containing app**, which records and writes the result into the App Group store; the user returns manually and the keyboard inserts the result.

Both flows insert via `UITextDocumentProxy.insertText(...)`.

Targets:

- `VoiceFlow` — containing app (onboarding, permissions, full history, vocabulary, settings, fallback-flow recording).
- `VoiceFlowKeyboard` — custom keyboard extension (primary-flow recording, insert, pending-insert UI, Next-Keyboard globe).
- `VoiceFlowTests`, `VoiceFlowUITests` — test targets.
- A shared, extension-safe Swift package or framework for models, store contracts, postprocessing rules, and the `SpeechEngine` protocol.

Shared App Group: `group.com.voiceflow.shared`.

---

## Current Repository State

The Xcode project **is scaffolded** at [`VoiceFlow/VoiceFlow.xcodeproj`](VoiceFlow/VoiceFlow.xcodeproj) with all four targets defined. Source files are stubs (default Xcode templates).

What is **not yet** wired up (Phase 0 prerequisites — see ROADMAP):

- App Group entitlements (`.entitlements` files for both targets).
- `RequestsOpenAccess = true` in [`VoiceFlow/VoiceFlowKeyboard/Info.plist`](VoiceFlow/VoiceFlowKeyboard/Info.plist) (currently `false`).
- Shared models (`DictationRecord`, `PendingInsert`, `VocabularyEntry`, `VoiceFlowSettings`).
- `SharedStoreClient` with the generation-counter concurrency protocol.
- `SpeechEngine` protocol and `AppleSpeechEngine`.
- `PostProcessor` rule pipeline.
- Onboarding screens.
- Deployment target reality-check (currently `26.4` in the project; the Phase 0 min-iOS investigation will set the real baseline).

Do not skip Phase 0. The roadmap is gated.

---

## Product Constraints

When making technical decisions, respect these iOS constraints:

- VoiceFlow cannot replace Apple's system dictation microphone button.
- VoiceFlow cannot intercept normal Apple dictation output.
- VoiceFlow shows its own microphone button **inside** the VoiceFlow keyboard UI.
- The Keyboard Extension inserts text through `UITextDocumentProxy.insertText(...)`.
- The containing app and Keyboard Extension communicate through App Groups using the generation-counter protocol described in `ROADMAP.md` → *App Group Concurrency Protocol*.
- Secure Fields, Phone Pads, and apps that disable third-party keyboards are expected iOS limits, **not** to be worked around with private APIs. They get clipboard fallback with a clear explanation.
- Keyboard Extension memory ceiling is ~48 MB. See `ROADMAP.md` → *Memory Budget* for the per-item budget.

---

## Implementation Preferences

- Swift + SwiftUI for the containing app.
- UIKit + `UIInputViewController` for the Keyboard Extension (SwiftUI-hosted views are acceptable where they remain stable inside extensions).
- Extension-safe shared code lives in its own framework / Swift package; app-only code stays in `VoiceFlow`.
- Apple Speech first. Whisper / Core ML is a **Phase 5** item, only if proven needed.
- Manual Insert in MVP. Auto-insert is post-MVP.
- Use Apple's MetricKit for crash / diagnostic reporting unless Phase 0 explicitly approves a third-party choice.
- Add tests around state models, shared store behavior, postprocessing, and insert-context rules as code lands.
- Performance budgets in `ROADMAP.md` → *Performance Budgets* are MVP exit criteria, not aspirational.

---

## Do Not Do

- No private iOS APIs.
- No simulating systemwide keyboard events.
- No Secure Field workarounds.
- No microphone access inside the Keyboard Extension **without** Open Access.
- No remote LLM path without explicit user approval and a privacy review.
- No silent network telemetry. Diagnostics stay local in the App Group store unless the user opts in.
- No edits to product copy, permissions wording, or App Review narrative without flagging it for human review — these are App-Review-sensitive.

---

## Working with this repo

- The canonical spec is `ROADMAP.md`. If there's a contradiction between code and roadmap, fix the code or update the roadmap explicitly — do not silently diverge.
- The `README.md` is reader-facing. Keep it short and pointed; product detail belongs in `ROADMAP.md`.
- Resolve merge conflicts before committing; do not commit `<<<<<<<` markers.
- The App Group ID `group.com.voiceflow.shared` must match in: project entitlements (both targets), `SharedStoreClient` source, and any docs that mention it. There is no other App Group ID in this project.

## Phase-0 prerequisites (the immediate work, in order)

1. Resolve any remaining doc inconsistencies introduced by edits.
2. Add `.entitlements` files for both targets with `com.apple.security.application-groups = ["group.com.voiceflow.shared"]`.
3. Set `RequestsOpenAccess = true` in the keyboard Info.plist.
4. Choose the deployment target after the min-iOS investigation; update the project settings.
5. Stand up the shared framework / Swift package with the model types listed in ROADMAP → *Data Model*.
6. Implement `SharedStoreClient` honoring the generation-counter protocol.
7. Run the spikes listed in ROADMAP → *Phase 0*. Each produces a written verdict.
8. Draft privacy nutrition label, App Review narrative, and onboarding copy.

Anything beyond this list is Phase 1+ and waits for Phase 0 sign-off.
