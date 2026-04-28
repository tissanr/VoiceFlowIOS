# Agent Guide (shared)

This file is the **single source of truth for AI agents** working in this repo — Codex, Claude Code, and any future tool. Agent-specific files (e.g., [`CLAUDE.md`](CLAUDE.md)) are thin pointers to this document and contain only operational notes that genuinely don't apply to other agents.

The product is described across [`ROADMAP.md`](ROADMAP.md) (index + phase status) and the focused specs in [`docs/specs/`](docs/specs/). Read the relevant spec before making any non-trivial change.

---

## Multi-agent contract

- This file's content stays **agent-neutral**. No "Codex says…" or "Claude says…" instructions in the body. Operational quirks of a specific agent go in that agent's pointer file (e.g., `CLAUDE.md` for Claude Code).
- Any agent that updates this file must keep it agent-neutral and must update the cross-references in the pointer files if section names change.
- If two agents are likely to disagree on a topic, this file decides for the project, not the agent.

---

## Documentation layout

```text
README.md                     - short reader-facing summary, links into the docs
AGENTS.md                     - this file: shared agent contract
CLAUDE.md                     - thin pointer; Claude-specific operational notes only
ROADMAP.md                    - index of specs, implementation status, phase plan
docs/specs/
  architecture.md             - iOS assumptions, dual-flow design, MVP scope, user flows
  data-and-storage.md         - App Group, models, shared-store concurrency protocol
  speech-and-postprocessing.md- audio session, SpeechEngine, postprocessing pipeline
  keyboard-and-insert.md      - keyboard UI states, insert path, edge cases
  performance-and-memory.md   - numeric memory / latency / energy budgets
  accessibility-and-localization.md
                              - VoiceOver, Dynamic Type, contrast, Localizable.xcstrings
  privacy-and-app-review.md   - permissions, Open Access policy, telemetry, App Review
  build-and-ci.md             - local build, CI pipeline, code signing, fastlane
  testing.md                  - Phase 0 spikes, MVP acceptance, regression matrix
```

### How the docs relate

- `ROADMAP.md` is an **index and status board**, not a place for deep design detail.
- Each `docs/specs/<topic>.md` is canonical for its topic. Cross-link, don't duplicate.
- The `README.md` is reader-facing and short. Detail belongs in the specs.
- If a spec topic doesn't exist yet, **add a new file under `docs/specs/`** and register it in the `ROADMAP.md` Specifications table — don't bloat an existing spec.

### Status conventions

Each spec file has a header like:

```text
> Spec status: Accepted (v1) | Draft | Awaiting review | Superseded
> Implementation status: Not started | In progress | Done
> Last updated: YYYY-MM-DD
```

`ROADMAP.md` mirrors these statuses with emoji at-a-glance:

- 🟥 Not started
- 🟧 In progress
- 🟨 Awaiting review / Blocked
- 🟩 Done
- ⬛ Superseded

When you change a spec or move a phase forward:

1. Update the spec header (Spec status, Implementation status, Last updated).
2. Update the corresponding row in the `ROADMAP.md` Specifications table.
3. If a phase's exit criteria are met, flip its row in the Implementation status table.
4. If a spec is meaningfully reworked, bump its `(v1)` → `(v2)` and note what changed.

### When a spec changes

- Keep the spec self-contained — readers must be able to act on one spec without flipping to others, except for cross-references that are explicitly linked.
- Cross-links use **relative paths** (`docs/specs/data-and-storage.md`, `../specs/foo.md` from a sibling spec).
- If two specs disagree, fix the disagreement in the same change. Open conflicts are not allowed to land.

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

For deeper design detail see [`docs/specs/architecture.md`](docs/specs/architecture.md).

---

## Current repository state

The Xcode project **is scaffolded** at [`VoiceFlow/VoiceFlow.xcodeproj`](VoiceFlow/VoiceFlow.xcodeproj) with all four targets defined. Source files are stubs (default Xcode templates).

What is **already wired up** from Phase 0 scaffold hardening:

- App Group entitlements (`.entitlements` files for both targets) using `group.com.voiceflow.shared`.
- `RequestsOpenAccess = true` in [`VoiceFlow/VoiceFlowKeyboard/Info.plist`](VoiceFlow/VoiceFlowKeyboard/Info.plist).
- Extension-safe local Swift package [`VoiceFlow/VoiceFlowShared`](VoiceFlow/VoiceFlowShared) with shared model types.

What is **not yet** wired up (remaining Phase 0 prerequisites — see [`ROADMAP.md`](ROADMAP.md) → Phase 0):

- `SharedStoreClient` with the generation-counter concurrency protocol.
- `SpeechEngine` protocol and `AppleSpeechEngine`.
- `PostProcessor` rule pipeline.
- Onboarding screens.
- Implementation code beyond scaffold hardening and shared model definitions.

Do not skip Phase 0. The roadmap is gated.

---

## Product constraints

When making technical decisions, respect these iOS constraints:

- VoiceFlow cannot replace Apple's system dictation microphone button.
- VoiceFlow cannot intercept normal Apple dictation output.
- VoiceFlow shows its own microphone button **inside** the VoiceFlow keyboard UI.
- The Keyboard Extension inserts text through `UITextDocumentProxy.insertText(...)`.
- The containing app and Keyboard Extension communicate through App Groups using the generation-counter protocol described in [`docs/specs/data-and-storage.md`](docs/specs/data-and-storage.md).
- Secure Fields, Phone Pads, and apps that disable third-party keyboards are expected iOS limits, **not** to be worked around with private APIs. They get clipboard fallback with a clear explanation.
- Keyboard Extension memory ceiling is ~48 MB. See [`docs/specs/performance-and-memory.md`](docs/specs/performance-and-memory.md) for per-item budgets.

---

## Implementation preferences

- Swift + SwiftUI for the containing app.
- UIKit + `UIInputViewController` for the Keyboard Extension (SwiftUI-hosted views are acceptable where they remain stable inside extensions).
- Extension-safe shared code lives in its own framework / Swift package; app-only code stays in `VoiceFlow`.
- Apple Speech first. Whisper / Core ML is a **Phase 5** item, only if proven needed.
- Manual Insert in MVP. Auto-insert is post-MVP.
- Use Apple's MetricKit for crash / diagnostic reporting unless Phase 0 explicitly approves a third-party choice.
- Add tests around state models, shared store behavior, postprocessing, and insert-context rules as code lands.
- Performance budgets in [`docs/specs/performance-and-memory.md`](docs/specs/performance-and-memory.md) are MVP exit criteria, not aspirational.

---

## Do not

- No private iOS APIs.
- No simulating systemwide keyboard events.
- No Secure Field workarounds.
- No microphone access inside the Keyboard Extension **without** Open Access.
- No remote LLM path without explicit user approval and a privacy review.
- No silent network telemetry. Diagnostics stay local in the App Group store unless the user opts in.
- No edits to product copy, permission strings, or the App Review narrative without flagging it for human review — these are App-Review-sensitive.

---

## Working with this repo

- The canonical detail is in `docs/specs/`. If there's a contradiction between code and a spec, fix the code or update the spec explicitly — do not silently diverge.
- The `README.md` is reader-facing. Keep it short and pointed; product detail belongs in the specs.
- Resolve merge conflicts before committing; do not commit `<<<<<<<` markers.
- The App Group ID `group.com.voiceflow.shared` must match in: project entitlements (both targets), `SharedStoreClient` source, and any docs that mention it. There is no other App Group ID in this project.
- When you finish work that moves a phase or a spec forward, update the status in **both** the spec header and the `ROADMAP.md` tables.

---

## Phase-0 prerequisites (the immediate work, in order)

1. Resolve any remaining doc inconsistencies introduced by edits.
2. Add `.entitlements` files for both targets with `com.apple.security.application-groups = ["group.com.voiceflow.shared"]`. **Done.**
3. Set `RequestsOpenAccess = true` in the keyboard `Info.plist`. **Done.**
4. Choose the deployment target after the min-iOS investigation; update the project settings. **Done:** iOS 17.0 selected in [`docs/spikes/min-ios-investigation.md`](docs/spikes/min-ios-investigation.md).
5. Stand up the shared framework / Swift package with the model types listed in [`docs/specs/data-and-storage.md`](docs/specs/data-and-storage.md). **Done:** [`VoiceFlow/VoiceFlowShared`](VoiceFlow/VoiceFlowShared).
6. Implement `SharedStoreClient` honoring the generation-counter protocol.
7. Run the spikes listed in [`ROADMAP.md`](ROADMAP.md) → Phase 0. Each produces a written verdict.
8. Draft privacy nutrition label, App Review narrative, and onboarding copy.

Anything beyond this list is Phase 1+ and waits for Phase 0 sign-off.
