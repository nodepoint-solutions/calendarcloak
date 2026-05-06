# Tray Menu Summary & Timestamp Fix

## Problem

1. The tray menu shows a "SYNCED CALENDARS" list that takes up space without adding much value at a glance.
2. "Last sync" always reads "in 0 seconds" because the relative label is computed once at render time and never refreshes — the view only re-renders when `AppState` changes, which doesn't happen between syncs.

## Design

### Status section

Replace the two-line status block (dot + status label, then last sync caption) with a three-line block:

```
● Active
Watching N calendars
Last sync: 2 minutes ago
```

- "Watching N calendars" uses `state.activeCalendarNames.count` — already populated by `SyncEngine` after each reconciliation.
- When `activeCalendarNames` is empty (no calendars configured yet), omit that line entirely.

### Remove calendar section

Remove `calendarSection` entirely — the list of calendar names and its surrounding `Divider()`. The second `Divider()` (before Settings) stays.

### Fix relative timestamp

Wrap the "Last sync" `Text` in a `TimelineView(.everyMinute)` so SwiftUI re-evaluates `Date()` automatically each minute. No state changes required.

## Files Changed

- `BeeBusy/UI/TrayMenuView.swift` — only file affected
