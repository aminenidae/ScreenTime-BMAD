# UI Polish Workstream

## Plan
- Normalize default points/minute so every new learning or reward app enters the system at 10 pts.
- Simplify the learning and reward tabs by removing per-row controls (delete, lock, toggle, point adjusters) in favor of cleaner summaries.
- Retire the CategoryAssignment modal in favor of auto-applying picker selections with the standardized 10 pts/min rate.
- Document the UI changes so future polishing efforts can reference the rationale and affected surfaces.

## Actions
- Updated `AppUsageViewModel`, `ScreenTimeService`, and `CategoryAssignmentView` to seed new selections with a 10 pts/min default so snapshots, persistence, and manual assignment all agree.
- Trimmed `LearningTabView` rows down to icon + copy, dropping the delete icon and point stepper while keeping the smaller icon sizing introduced earlier.
- Simplified `RewardsTabView` cards to mirror the learning layout by removing the lock/toggle UI and the point adjuster, including cleanup of unused helpers/styles.
- Disabled the CategoryAssignment sheet hookups in `MainTabView`/`AppUsageView`, then taught `AppUsageViewModel` to auto-assign picker selections (learning/reward) at 10 pts/min and immediately block+monitor without any modal handoff.
- Implemented a shared `TabTopBar` to give the Learning and Reward tabs the same header styling as Settings, removed the Settings “Done” button, and wired every chevron (including the new ones on both challenge tabs) to `SessionManager.exitToSelection()` so parents can jump straight back to the profile selector from any tab.
