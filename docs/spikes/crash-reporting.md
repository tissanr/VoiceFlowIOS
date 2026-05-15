# Phase 0 Spike: Crash Reporting

> **Verdict:** Use MetricKit first; defer third-party crash SDKs.
> **Date:** 2026-05-15
> **Status:** Done.

## Question

Should VoiceFlow use Apple's MetricKit or a third-party crash reporter for the MVP?

## Decision

Use **MetricKit** for MVP crash and diagnostics reporting. Do not add Sentry, Firebase Crashlytics, or another networked crash SDK in Phase 0.

MetricKit matches the MVP privacy posture:

- It is first-party Apple infrastructure.
- It does not require a network SDK inside the Keyboard Extension.
- It keeps the default diagnostic path local / system-mediated.
- It avoids expanding the App Store privacy nutrition label before the product has proven need for network telemetry.

Third-party crash reporting can be reconsidered after TestFlight if MetricKit plus local diagnostics does not provide enough crash attribution.

## Sources Checked

- [Apple Developer Documentation: MetricKit](https://developer.apple.com/documentation/metrickit) receives on-device diagnostics and power/performance reports, including crash diagnostics.
- [Apple Developer Documentation: `MXMetricManager`](https://developer.apple.com/documentation/metrickit/mxmetricmanager) delivers metric and diagnostic payloads through an app subscriber.

## Evaluation

| Option | Advantages | Problems for VoiceFlow | Verdict |
| --- | --- | --- | --- |
| MetricKit | First-party, privacy-friendly, no app-owned network telemetry, includes crash diagnostics and performance metrics | Delivery is not a real-time product analytics stream; extension attribution may need supplemental breadcrumbs | Use for MVP |
| Sentry / Crashlytics / similar | Better dashboards, alerting, release tracking, richer grouping | Adds SDK + network telemetry, complicates Keyboard Extension Open Access posture, requires privacy-policy and nutrition-label review | Defer |
| Local-only diagnostic log | Simple, extension-safe when stored in App Group, user-visible/exportable | Does not capture hard crashes by itself | Use as supplement |

## Implementation Shape

Phase 1 should add a small diagnostics subsystem:

- Containing app subscribes to MetricKit early in app launch.
- Containing app persists the latest relevant MetricKit diagnostic summaries into the App Group store.
- Keyboard Extension writes local lifecycle breadcrumbs to the App Group store, such as launch, recording start, recording stop, insert attempt, and clean teardown.
- Settings shows a local Diagnostics view with "Last keyboard error" and recent breadcrumbs.
- Any "share diagnostics" action is explicit user action; diagnostics are not silently uploaded.

## Guardrails

- Do not add a third-party crash SDK without a new privacy review.
- Do not upload diagnostics automatically.
- Do not persist raw audio in diagnostics.
- Do not include dictated text in crash or breadcrumb payloads unless the user explicitly exports it for support.

## Open Risk

MetricKit should not be treated as the only source of truth for Keyboard Extension failures. Extension lifecycle breadcrumbs are required because extension terminations can be caused by memory pressure, host-app behavior, or keyboard lifecycle events that may not arrive as a clean crash report.

## Follow-up

1. Add a MetricKit subscriber in the containing app during Phase 1.
2. Add an extension-safe diagnostics ring buffer to the shared package.
3. Add a Settings diagnostics screen after the first end-to-end flow exists.
4. Revisit third-party crash reporting only if TestFlight shows MetricKit + local breadcrumbs are insufficient.
