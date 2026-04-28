# Spec: Performance & Memory

> **Spec status:** Accepted (v1)
> **Implementation status:** Not started (budgets unverified, Phase 0 pending)
> **Last updated:** 2026-04-28
> **Owners:** iOS

Numeric budgets. These are MVP exit criteria, not aspirational.

---

## Memory budget — Keyboard Extension

iOS terminates Keyboard Extensions that exceed roughly **48 MB** resident memory. The MVP must not load history, vocabulary, or models eagerly inside the extension.

| Item | Budget | Notes |
| --- | --- | --- |
| Total resident extension memory | < 30 MB sustained, < 45 MB peak | Leave headroom for the system. |
| `PendingInsert` cache | < 8 KB | Single record. |
| Vocabulary loaded in-extension | ≤ 200 entries OR < 64 KB | Lazy-loaded; rest stays in containing app. |
| History loaded in-extension | last 5 entries only | Full history lives only in the app. |
| Speech recognition (primary flow) | measured in Phase 0 spike | If the spike shows we cannot stay under budget with live recognition, primary flow is restricted to capable device classes; affected users get the fallback flow. |

**Phase 0 in-keyboard recording spike** must measure peak memory on real devices and produce a memory-budget verdict.

---

## Memory budget — containing app

| Item | Budget |
| --- | --- |
| Containing app peak memory during recording | < 120 MB |
| Containing app peak memory at history-list render (200 entries) | < 80 MB |

---

## Latency budgets

| Metric | Target | Hard ceiling |
| --- | --- | --- |
| Cold app launch (containing app) — first interactive frame | < 700 ms | 1.2 s |
| Keyboard load (first appearance after activation) | < 250 ms | 500 ms |
| Tap-to-record start latency (primary flow) | < 300 ms | 600 ms |
| End-of-recording → final text on screen (≤ 10 s of audio) | < 800 ms | 2 s |
| Insert latency (Insert tap → text appears) | < 100 ms | 250 ms |

---

## Energy budget

| Metric | Target | Hard ceiling |
| --- | --- | --- |
| Battery cost per minute of recording (iPhone 13) | < 1.5 % | 3 % |
| Background app refresh cost when idle | 0 — VoiceFlow does no background work | — |

---

## Validation

- Phase 0 spike establishes preliminary numbers on the chosen iOS baseline.
- Phase 1 acceptance requires meeting all targets on a representative device (iPhone 12 or newer).
- Phase 4 re-validates all numbers on the **lowest-supported** device class. Deviations must be fixed or explicitly accepted with a written justification.

Use Instruments (Time Profiler, Allocations, Energy Log) and MetricKit reports for measurement.

---

## Cross-references

- Telemetry source for in-the-wild measurement: [privacy-and-app-review.md](privacy-and-app-review.md) → Telemetry & Crash Reporting
- Memory rules for what loads in the extension: [data-and-storage.md](data-and-storage.md)
