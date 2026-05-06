# Event Filters, App Rename Stamp & Legacy Migration

**Date:** 2026-05-07  
**Status:** Approved

---

## Overview

Three related changes:

1. **Event filter settings** — users can limit which events are mirrored as Busy blocks (work-hours window, all-day toggle)
2. **App rename stamp** — busy-event description marker changes from `bee-busy:source=` to `calendarcloak:source=`
3. **Legacy migration** — on startup, delete any events stamped with the old prefix so reconciliation organically recreates them with the new stamp

---

## 1. AppSettings — new keys

Four new `UserDefaults`-backed properties added to `AppSettings`:

| Key | Type | Default | Meaning |
|-----|------|---------|---------|
| `includeAllDayEvents` | `Bool` | `true` | Whether all-day events are mirrored |
| `workHoursEnabled` | `Bool` | `false` | Whether the work-hours window is active |
| `workHoursStart` | `Int` | `9` | Inclusive start hour (0–23) |
| `workHoursEnd` | `Int` | `18` | Exclusive end hour (1–24); must be > start |

All follow the same `access`/`withMutation` pattern used by existing properties.

---

## 2. EventEligibility — settings-aware filtering

`isEligible` gains a `settings: AppSettings` parameter. Filtering logic:

```
guard !BusyEventMarker.isBusyEvent(event) else { return false }
guard event.isAccepted else { return false }

if event.isAllDay {
    return settings.includeAllDayEvents
}

if settings.workHoursEnabled {
    let hour = Calendar.current.component(.hour, from: event.startDate)
    guard hour >= settings.workHoursStart && hour < settings.workHoursEnd else { return false }
}

return true
```

All-day events bypass the hours check entirely — they are controlled only by `includeAllDayEvents`. The hours filter applies only to timed events.

Call sites updated: `SyncEngine.runReconciliation()` and `SyncEngine.dryRun()`.

Tests updated to pass a settings instance. New test cases cover:
- all-day event excluded when `includeAllDayEvents = false`
- timed event within work hours passes
- timed event outside work hours fails
- all-day event is not affected by `workHoursEnabled`

---

## 3. BusyEventMarker — rename prefix

```swift
// Before
private static let prefix = "bee-busy:source="

// After
private static let prefix = "calendarcloak:source="
private static let legacyPrefix = "bee-busy:source="

static func isLegacyBusyEvent(_ event: CalendarEvent) -> Bool {
    event.notes?.hasPrefix(legacyPrefix) == true
}
```

`notes(for:)` and `sourceID(from:)` continue to use `prefix` (now the new value). `isLegacyBusyEvent` is used only for the one-time migration sweep.

Existing test for `isBusyEvent` updated to use `calendarcloak:source=`. Legacy-prefix test added.

---

## 4. SyncEngine — legacy sweep

New method:

```swift
func deleteLegacyBusyEvents() {
    let calendarIDs = store.fetchAllCalendarIDs()
    guard !calendarIDs.isEmpty else { return }
    let events = store.fetchEvents(calendarIDs: calendarIDs, start: .distantPast, end: .distantFuture)
    let legacy = events.filter { BusyEventMarker.isLegacyBusyEvent($0) }
    for event in legacy { store.delete(event) }
    logger.info("Deleted \(legacy.count) legacy bee-busy events")
}
```

Called once in `AppCoordinator.bootstrap()` immediately before `engine.start()`.

---

## 5. SettingsView — Event Filters section

New `Section("Event Filters")` inserted after the look-forward window section:

```
[ Toggle ] Include all-day events

[ Toggle ] Filter by work hours
  [ Picker: "From" ] 9:00 AM ▼    [ Picker: "To" ] 6:00 PM ▼
  (pickers visible only when "Filter by work hours" is on)
```

Hour pickers display formatted strings ("12:00 AM" … "11:00 PM" for start; "1:00 AM" … "12:00 AM" for end). End options are constrained to hours > selected start to prevent invalid ranges.

---

## 6. README update

Under the **Settings** section, add:

- **Include all-day events** — whether all-day events are mirrored as Busy blocks (on by default)
- **Work hours filter** — when enabled, only events that start within the configured window are mirrored

---

## Files changed

| File | Change |
|------|--------|
| `CalendarCloak/Settings/AppSettings.swift` | Add 4 new settings |
| `CalendarCloak/Sync/EventEligibility.swift` | Add settings param and filter logic |
| `CalendarCloak/Domain/BusyEventMarker.swift` | Rename prefix, add legacyPrefix + isLegacyBusyEvent |
| `CalendarCloak/Sync/SyncEngine.swift` | Add deleteLegacyBusyEvents(), update isEligible call sites |
| `CalendarCloak/AppCoordinator.swift` | Call deleteLegacyBusyEvents() before engine.start() |
| `CalendarCloak/UI/SettingsView.swift` | Add Event Filters section |
| `CalendarCloakTests/EventEligibilityTests.swift` | Update + extend tests |
| `CalendarCloakTests/BusyEventMarkerTests.swift` | Update prefix string, add legacy test |
| `README.md` | Document new filter settings |
