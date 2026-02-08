# Technical Limitations, Workarounds & Policy Risk Assessment

## Summary
Phase 2 compliance and constraints testing surfaced manageable limitations. This report documents each issue, available mitigations, and the related product or policy risk rating.

## Technical Limitations & Workarounds

| Area | Limitation | Impact | Workaround / Mitigation |
| --- | --- | --- | --- |
| DeviceActivity offline gap | Usage updates pause when the child device remains offline or locked for >30 minutes | Data lag, inaccurate daily totals | Cache last known payload locally; send daily “unlock reminder” push; replay deferred events once connectivity resumes |
| Reward enforcement | Direct reward app locking blocked by Screen Time API scope | Cannot programmatically unlock third‑party apps | Shift to reward notifications + parental approval flow; explore Shortcuts automation for optional manual unlocking |
| Background processing budget | Continuous monitoring combined with CloudKit sync can exhaust background refresh | Missed sync windows, battery spike | Defer CloudKit sync until device is charging or actively used; throttle monitoring to top 3 categories |
| Data retention | FamilyControls tokens persist indefinitely by default | Unbounded storage, privacy risk | Schedule monthly purge and rotate tokens using background refresh job |
| ATT prompt text | ATT usage description must match collected metrics | App Store rejection risk | Finalize localized `NSPrivacyTrackingUsageDescription` referencing learning progress analytics |

## Policy & Platform Risk Assessment

| Risk | Description | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- | --- |
| Screen Time entitlement changes | Apple may restrict third-party access to DeviceActivity APIs | Medium | High | Track WWDC / release notes; maintain alternate “manual logging” mode gated behind feature flag |
| FamilyControls approval | App review could require justification for child data handling | Medium | High | Prepare privacy dossier (flow diagrams, ATT copy, retention policy); ensure parental consent flow is first-run blocking |
| COPPA/GDPR updates | Regulation may tighten data minimization requirements | Low | High | Keep retention <=12 months; implement export/delete tooling prior to GA |
| Battery usage enforcement | App Store rejects if energy usage exceeds norms | Low | Medium | Monitor with `MetricKit`; add automated battery regression checks in nightly builds |

## Recommendations
1. Implement reminder notification & deferred event replay backlog in upcoming sprint.
2. Add automated data-retention purge task to backlog (cron-style background refresh).
3. Draft privacy dossier and update ATT copy prior to TestFlight submission.
4. Keep reward flow design focused on parental approval/notifications rather than direct app unlocking.

## Next Actions
- Feed mitigations into PHASE2_IMPLEMENTATION_PLAN checklist.
- Review risks with Product & Legal during next feasibility checkpoint meeting.
