# Event Filters, App Rename Stamp & Legacy Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add work-hours and all-day event filters to Settings, rename the busy-event stamp from `bee-busy:source=` to `calendarcloak:source=`, and sweep legacy stamped events on startup.

**Architecture:** Filter settings live in `AppSettings` (UserDefaults-backed). `EventEligibility.isEligible` gains a `settings:` parameter and applies the filters. `BusyEventMarker` gets a new prefix and a legacy-detection helper. `SyncEngine` gets a one-shot `deleteLegacyBusyEvents()` called from `AppCoordinator.bootstrap()` before `engine.start()`. `SettingsView` gets a new "Event Filters" section.

**Tech Stack:** Swift, SwiftUI, EventKit, XCTest, xcodebuild (`make test`)

---

## File Map

| File | Change |
|------|--------|
| `CalendarCloak/Domain/BusyEventMarker.swift` | Rename prefix; add `legacyPrefix` + `isLegacyBusyEvent(_:)` |
| `CalendarCloakTests/BusyEventMarkerTests.swift` | Update prefix strings; add legacy-detection tests |
| `CalendarCloak/Settings/AppSettings.swift` | Add 4 new UserDefaults-backed properties |
| `CalendarCloak/Sync/EventEligibility.swift` | Add `settings:` param; apply all-day + hours filters |
| `CalendarCloakTests/EventEligibilityTests.swift` | Update call sites; add filter test cases |
| `CalendarCloak/Sync/SyncEngine.swift` | Update `isEligible` call sites; add `deleteLegacyBusyEvents()` |
| `CalendarCloakTests/SyncEngineTests.swift` | Add `deleteLegacyBusyEvents` tests |
| `CalendarCloak/AppCoordinator.swift` | Call `deleteLegacyBusyEvents()` before `engine.start()` |
| `CalendarCloak/UI/SettingsView.swift` | Add "Event Filters" section |
| `README.md` | Document the two new filter settings |

---

### Task 1: Rename BusyEventMarker prefix and add legacy detection

**Files:**
- Modify: `CalendarCloak/Domain/BusyEventMarker.swift`
- Modify: `CalendarCloakTests/BusyEventMarkerTests.swift`

- [ ] **Step 1: Update BusyEventMarkerTests to expect the new prefix and add legacy tests**

Replace the entire file:

```swift
import XCTest
@testable import CalendarCloak

final class BusyEventMarkerTests: XCTestCase {

    func test_notes_containsPrefix() {
        let notes = BusyEventMarker.notes(for: "abc123")
        XCTAssertEqual(notes, "calendarcloak:source=abc123")
    }

    func test_sourceID_extractsFromValidNotes() {
        let notes = "calendarcloak:source=abc123"
        XCTAssertEqual(BusyEventMarker.sourceID(from: notes), "abc123")
    }

    func test_sourceID_returnsNilForNonBusyNotes() {
        XCTAssertNil(BusyEventMarker.sourceID(from: "just a regular note"))
    }

    func test_sourceID_returnsNilForNilNotes() {
        XCTAssertNil(BusyEventMarker.sourceID(from: nil))
    }

    func test_isBusyEvent_trueWhenMarkerPresent() {
        let event = CalendarEvent(
            id: "id1", calendarID: "cal1", calendarName: "Work",
            title: "Busy", startDate: Date(), endDate: Date(),
            isAllDay: false, notes: "calendarcloak:source=abc123", isAccepted: true
        )
        XCTAssertTrue(BusyEventMarker.isBusyEvent(event))
    }

    func test_isBusyEvent_falseWhenNoMarker() {
        let event = CalendarEvent(
            id: "id2", calendarID: "cal1", calendarName: "Work",
            title: "Team standup", startDate: Date(), endDate: Date(),
            isAllDay: false, notes: nil, isAccepted: true
        )
        XCTAssertFalse(BusyEventMarker.isBusyEvent(event))
    }

    func test_isBusyEvent_falseWhenNotesAreUnrelated() {
        let event = CalendarEvent(
            id: "id3", calendarID: "cal1", calendarName: "Work",
            title: "Busy", startDate: Date(), endDate: Date(),
            isAllDay: false, notes: "Do not disturb", isAccepted: true
        )
        XCTAssertFalse(BusyEventMarker.isBusyEvent(event))
    }

    func test_sourceID_returnsNilForPrefixOnlyNotes() {
        XCTAssertNil(BusyEventMarker.sourceID(from: "calendarcloak:source="))
    }

    func test_roundTrip_sourceIDSurvivesMarkerEncoding() {
        let id = "X5A2F-CAFE-001"
        XCTAssertEqual(BusyEventMarker.sourceID(from: BusyEventMarker.notes(for: id)), id)
    }

    // Legacy detection

    func test_isLegacyBusyEvent_trueForOldPrefix() {
        let event = CalendarEvent(
            id: "id4", calendarID: "cal1", calendarName: "Work",
            title: "Busy", startDate: Date(), endDate: Date(),
            isAllDay: false, notes: "bee-busy:source=abc123", isAccepted: true
        )
        XCTAssertTrue(BusyEventMarker.isLegacyBusyEvent(event))
    }

    func test_isLegacyBusyEvent_falseForNewPrefix() {
        let event = CalendarEvent(
            id: "id5", calendarID: "cal1", calendarName: "Work",
            title: "Busy", startDate: Date(), endDate: Date(),
            isAllDay: false, notes: "calendarcloak:source=abc123", isAccepted: true
        )
        XCTAssertFalse(BusyEventMarker.isLegacyBusyEvent(event))
    }

    func test_isLegacyBusyEvent_falseForNoNotes() {
        let event = CalendarEvent(
            id: "id6", calendarID: "cal1", calendarName: "Work",
            title: "Meeting", startDate: Date(), endDate: Date(),
            isAllDay: false, notes: nil, isAccepted: true
        )
        XCTAssertFalse(BusyEventMarker.isLegacyBusyEvent(event))
    }
}
```

- [ ] **Step 2: Run tests — expect failures on the prefix-string assertions**

```bash
make test 2>&1 | grep -E "(Test Case|FAILED|passed|failed)"
```

Expected: several `BusyEventMarkerTests` failures referencing `calendarcloak:source=` vs `bee-busy:source=`.

- [ ] **Step 3: Update BusyEventMarker.swift**

```swift
import Foundation

enum BusyEventMarker {
    private static let prefix = "calendarcloak:source="
    private static let legacyPrefix = "bee-busy:source="

    static func notes(for sourceID: String) -> String {
        "\(prefix)\(sourceID)"
    }

    static func sourceID(from notes: String?) -> String? {
        guard let notes, notes.hasPrefix(prefix) else { return nil }
        let extracted = String(notes.dropFirst(prefix.count))
        return extracted.isEmpty ? nil : extracted
    }

    static func isBusyEvent(_ event: CalendarEvent) -> Bool {
        sourceID(from: event.notes) != nil
    }

    static func isLegacyBusyEvent(_ event: CalendarEvent) -> Bool {
        event.notes?.hasPrefix(legacyPrefix) == true
    }
}
```

- [ ] **Step 4: Also update the hardcoded legacy string in EventEligibilityTests**

`CalendarCloakTests/EventEligibilityTests.swift` line 24 references `"bee-busy:source=abc123"`. Update it:

```swift
// line 24 — change from:
let busyEvent = makeEvent(isAccepted: true, notes: "bee-busy:source=abc123")
// to:
let busyEvent = makeEvent(isAccepted: true, notes: "calendarcloak:source=abc123")
```

- [ ] **Step 5: Run tests — all BusyEventMarkerTests and EventEligibilityTests should pass**

```bash
make test 2>&1 | grep -E "(Test Case|FAILED|passed|failed)"
```

Expected: all BusyEventMarkerTests and EventEligibilityTests pass.

- [ ] **Step 6: Commit**

```bash
git add CalendarCloak/Domain/BusyEventMarker.swift \
        CalendarCloakTests/BusyEventMarkerTests.swift \
        CalendarCloakTests/EventEligibilityTests.swift
git commit -m "feat: rename busy-event stamp to calendarcloak:source="
```

---

### Task 2: Add filter settings to AppSettings

**Files:**
- Modify: `CalendarCloak/Settings/AppSettings.swift`

No new unit tests — the properties are thin UserDefaults wrappers exercised indirectly by EventEligibility tests in Task 3.

- [ ] **Step 1: Add the four new properties to AppSettings.swift**

Append after the `hasCompletedSetup` property, before the closing `}`:

```swift
    var includeAllDayEvents: Bool {
        get {
            access(keyPath: \.includeAllDayEvents)
            guard defaults.object(forKey: "includeAllDayEvents") != nil else { return true }
            return defaults.bool(forKey: "includeAllDayEvents")
        }
        set {
            withMutation(keyPath: \.includeAllDayEvents) {
                defaults.set(newValue, forKey: "includeAllDayEvents")
            }
        }
    }

    var workHoursEnabled: Bool {
        get {
            access(keyPath: \.workHoursEnabled)
            return defaults.bool(forKey: "workHoursEnabled")
        }
        set {
            withMutation(keyPath: \.workHoursEnabled) {
                defaults.set(newValue, forKey: "workHoursEnabled")
            }
        }
    }

    var workHoursStart: Int {
        get {
            access(keyPath: \.workHoursStart)
            guard defaults.object(forKey: "workHoursStart") != nil else { return 9 }
            return defaults.integer(forKey: "workHoursStart")
        }
        set {
            withMutation(keyPath: \.workHoursStart) {
                defaults.set(newValue, forKey: "workHoursStart")
            }
        }
    }

    var workHoursEnd: Int {
        get {
            access(keyPath: \.workHoursEnd)
            guard defaults.object(forKey: "workHoursEnd") != nil else { return 18 }
            return defaults.integer(forKey: "workHoursEnd")
        }
        set {
            withMutation(keyPath: \.workHoursEnd) {
                defaults.set(newValue, forKey: "workHoursEnd")
            }
        }
    }
```

- [ ] **Step 2: Build to confirm no compile errors**

```bash
make build 2>&1 | grep -E "(error:|BUILD SUCCEEDED|BUILD FAILED)"
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Commit**

```bash
git add CalendarCloak/Settings/AppSettings.swift
git commit -m "feat: add includeAllDayEvents and workHours filter settings"
```

---

### Task 3: Settings-aware EventEligibility filtering

**Files:**
- Modify: `CalendarCloak/Sync/EventEligibility.swift`
- Modify: `CalendarCloakTests/EventEligibilityTests.swift`
- Modify: `CalendarCloak/Sync/SyncEngine.swift` (two call sites)

- [ ] **Step 1: Write the new EventEligibilityTests**

Replace the entire file:

```swift
import XCTest
@testable import CalendarCloak

final class EventEligibilityTests: XCTestCase {

    private func makeSettings(
        includeAllDay: Bool = true,
        workHoursEnabled: Bool = false,
        workHoursStart: Int = 9,
        workHoursEnd: Int = 18
    ) -> AppSettings {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let s = AppSettings(defaults: defaults)
        s.includeAllDayEvents = includeAllDay
        s.workHoursEnabled = workHoursEnabled
        s.workHoursStart = workHoursStart
        s.workHoursEnd = workHoursEnd
        return s
    }

    private func makeEvent(
        isAccepted: Bool,
        notes: String? = nil,
        isAllDay: Bool = false,
        startDate: Date = Date()
    ) -> CalendarEvent {
        CalendarEvent(
            id: UUID().uuidString, calendarID: "cal1", calendarName: "Work",
            title: "Meeting", startDate: startDate,
            endDate: startDate.addingTimeInterval(3600),
            isAllDay: isAllDay, notes: notes, isAccepted: isAccepted
        )
    }

    // MARK: - Existing behaviour

    func test_acceptedEvent_isEligible() {
        XCTAssertTrue(EventEligibility.isEligible(makeEvent(isAccepted: true), settings: makeSettings()))
    }

    func test_notAcceptedEvent_isNotEligible() {
        XCTAssertFalse(EventEligibility.isEligible(makeEvent(isAccepted: false), settings: makeSettings()))
    }

    func test_busyEventWithMarker_isNotEligible() {
        let busyEvent = makeEvent(isAccepted: true, notes: "calendarcloak:source=abc123")
        XCTAssertFalse(EventEligibility.isEligible(busyEvent, settings: makeSettings()))
    }

    // MARK: - All-day filter

    func test_allDayEvent_eligibleWhenIncludeAllDayIsTrue() {
        let settings = makeSettings(includeAllDay: true)
        XCTAssertTrue(EventEligibility.isEligible(makeEvent(isAccepted: true, isAllDay: true), settings: settings))
    }

    func test_allDayEvent_notEligibleWhenIncludeAllDayIsFalse() {
        let settings = makeSettings(includeAllDay: false)
        XCTAssertFalse(EventEligibility.isEligible(makeEvent(isAccepted: true, isAllDay: true), settings: settings))
    }

    func test_allDayEvent_ignoredByWorkHoursFilter() {
        // All-day events bypass the hours check; controlled only by includeAllDayEvents.
        let settings = makeSettings(includeAllDay: true, workHoursEnabled: true, workHoursStart: 9, workHoursEnd: 18)
        XCTAssertTrue(EventEligibility.isEligible(makeEvent(isAccepted: true, isAllDay: true), settings: settings))
    }

    // MARK: - Work hours filter

    func test_timedEvent_withinWorkHours_isEligible() {
        let settings = makeSettings(workHoursEnabled: true, workHoursStart: 9, workHoursEnd: 18)
        let start = dateWithHour(10)
        XCTAssertTrue(EventEligibility.isEligible(makeEvent(isAccepted: true, startDate: start), settings: settings))
    }

    func test_timedEvent_beforeWorkHours_isNotEligible() {
        let settings = makeSettings(workHoursEnabled: true, workHoursStart: 9, workHoursEnd: 18)
        let start = dateWithHour(8)
        XCTAssertFalse(EventEligibility.isEligible(makeEvent(isAccepted: true, startDate: start), settings: settings))
    }

    func test_timedEvent_atWorkHoursEnd_isNotEligible() {
        // End is exclusive: an event starting exactly at workHoursEnd is outside the window.
        let settings = makeSettings(workHoursEnabled: true, workHoursStart: 9, workHoursEnd: 18)
        let start = dateWithHour(18)
        XCTAssertFalse(EventEligibility.isEligible(makeEvent(isAccepted: true, startDate: start), settings: settings))
    }

    func test_timedEvent_workHoursDisabled_ignoredByHoursCheck() {
        let settings = makeSettings(workHoursEnabled: false, workHoursStart: 9, workHoursEnd: 18)
        let start = dateWithHour(7)  // outside hours, but filter is off
        XCTAssertTrue(EventEligibility.isEligible(makeEvent(isAccepted: true, startDate: start), settings: settings))
    }

    // MARK: - Helpers

    private func dateWithHour(_ hour: Int) -> Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = hour
        components.minute = 0
        components.second = 0
        return Calendar.current.date(from: components)!
    }
}
```

- [ ] **Step 2: Run tests — expect compile errors (settings param missing)**

```bash
make test 2>&1 | grep -E "(error:|Test Case|FAILED|passed|failed)"
```

Expected: compile errors because `EventEligibility.isEligible` doesn't accept a `settings:` parameter yet.

- [ ] **Step 3: Update EventEligibility.swift**

```swift
import Foundation

enum EventEligibility {
    static func isEligible(_ event: CalendarEvent, settings: AppSettings) -> Bool {
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
    }
}
```

- [ ] **Step 4: Update the two call sites in SyncEngine.swift**

In `runReconciliation()` (line ~99):
```swift
// before:
let eligible = sources.filter { EventEligibility.isEligible($0) }
// after:
let eligible = sources.filter { EventEligibility.isEligible($0, settings: settings) }
```

In `dryRun(calendarIDs:)` (line ~64):
```swift
// before:
let eligible = sources.filter { EventEligibility.isEligible($0) }
// after:
let eligible = sources.filter { EventEligibility.isEligible($0, settings: settings) }
```

- [ ] **Step 5: Run tests — all EventEligibilityTests should pass**

```bash
make test 2>&1 | grep -E "(Test Case|FAILED|passed|failed)"
```

Expected: all EventEligibilityTests pass; no other test regressions.

- [ ] **Step 6: Commit**

```bash
git add CalendarCloak/Sync/EventEligibility.swift \
        CalendarCloak/Sync/SyncEngine.swift \
        CalendarCloakTests/EventEligibilityTests.swift
git commit -m "feat: add work-hours and all-day filters to EventEligibility"
```

---

### Task 4: deleteLegacyBusyEvents in SyncEngine + AppCoordinator

**Files:**
- Modify: `CalendarCloak/Sync/SyncEngine.swift`
- Modify: `CalendarCloakTests/SyncEngineTests.swift`
- Modify: `CalendarCloak/AppCoordinator.swift`

- [ ] **Step 1: Write failing tests for deleteLegacyBusyEvents**

In `CalendarCloakTests/SyncEngineTests.swift`, add after the existing `deleteAllBusyEvents` tests:

```swift
    // MARK: - deleteLegacyBusyEvents

    func test_deleteLegacyBusyEvents_deletesEventsWithOldPrefix() {
        let store = MockCalendarStore()
        store.stubbedCalendarIDs = ["calA"]
        store.stubbedEvents = [
            CalendarEvent(
                id: "legacy1", calendarID: "calA", calendarName: "calA",
                title: "Busy", startDate: Date(), endDate: Date().addingTimeInterval(3600),
                isAllDay: false, notes: "bee-busy:source=OLD-ID-123", isAccepted: true
            )
        ]
        let engine = makeEngine(store: store)

        engine.deleteLegacyBusyEvents()

        XCTAssertEqual(store.deletedEvents.count, 1)
        XCTAssertEqual(store.deletedEvents.first?.id, "legacy1")
    }

    func test_deleteLegacyBusyEvents_doesNotDeleteNewPrefixEvents() {
        let store = MockCalendarStore()
        store.stubbedCalendarIDs = ["calA"]
        store.stubbedEvents = [
            CalendarEvent(
                id: "new1", calendarID: "calA", calendarName: "calA",
                title: "Busy", startDate: Date(), endDate: Date().addingTimeInterval(3600),
                isAllDay: false, notes: "calendarcloak:source=NEW-ID-456", isAccepted: true
            )
        ]
        let engine = makeEngine(store: store)

        engine.deleteLegacyBusyEvents()

        XCTAssertEqual(store.deletedEvents.count, 0)
    }

    func test_deleteLegacyBusyEvents_doesNotDeleteSourceEvents() {
        let store = MockCalendarStore()
        store.stubbedCalendarIDs = ["calA"]
        store.stubbedEvents = [
            CalendarEvent(
                id: "src1", calendarID: "calA", calendarName: "calA",
                title: "Team standup", startDate: Date(), endDate: Date().addingTimeInterval(3600),
                isAllDay: false, notes: nil, isAccepted: true
            )
        ]
        let engine = makeEngine(store: store)

        engine.deleteLegacyBusyEvents()

        XCTAssertEqual(store.deletedEvents.count, 0)
    }
```

- [ ] **Step 2: Run tests — expect compile error (deleteLegacyBusyEvents not defined)**

```bash
make test 2>&1 | grep -E "(error:|Test Case|FAILED|passed|failed)"
```

Expected: compile error `value of type 'SyncEngine' has no member 'deleteLegacyBusyEvents'`.

- [ ] **Step 3: Add deleteLegacyBusyEvents to SyncEngine.swift**

Add after `deleteAllBusyEvents()`:

```swift
    func deleteLegacyBusyEvents() {
        let calendarIDs = store.fetchAllCalendarIDs()
        guard !calendarIDs.isEmpty else { return }
        let events = store.fetchEvents(calendarIDs: calendarIDs, start: .distantPast, end: .distantFuture)
        let legacy = events.filter { BusyEventMarker.isLegacyBusyEvent($0) }
        for event in legacy {
            store.delete(event)
        }
        logger.info("Deleted \(legacy.count) legacy bee-busy events")
    }
```

- [ ] **Step 4: Run tests — new SyncEngineTests should pass**

```bash
make test 2>&1 | grep -E "(Test Case|FAILED|passed|failed)"
```

Expected: all three new `deleteLegacyBusyEvents` tests pass; no regressions.

- [ ] **Step 5: Update AppCoordinator.swift to call deleteLegacyBusyEvents before engine.start()**

In `bootstrap()`, the branch that calls `engine.start()`:

```swift
// before:
if settings.hasCompletedSetup && settings.selectedCalendarIDs.count >= 2 {
    engine.start()

// after:
if settings.hasCompletedSetup && settings.selectedCalendarIDs.count >= 2 {
    engine.deleteLegacyBusyEvents()
    engine.start()
```

- [ ] **Step 6: Build to confirm no compile errors**

```bash
make build 2>&1 | grep -E "(error:|BUILD SUCCEEDED|BUILD FAILED)"
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 7: Commit**

```bash
git add CalendarCloak/Sync/SyncEngine.swift \
        CalendarCloak/AppCoordinator.swift \
        CalendarCloakTests/SyncEngineTests.swift
git commit -m "feat: delete legacy bee-busy events on startup"
```

---

### Task 5: Event Filters section in SettingsView

**Files:**
- Modify: `CalendarCloak/UI/SettingsView.swift`

No unit tests — this is a SwiftUI view change; verify visually via `make run`.

- [ ] **Step 1: Add the Event Filters section to SettingsView.swift**

Add a private helper and the new section. Insert `hourLabel(_:)` as a private method inside `SettingsView`:

```swift
    private func hourLabel(_ hour: Int) -> String {
        var components = DateComponents()
        components.hour = hour
        components.minute = 0
        let date = Calendar.current.date(from: components) ?? Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
```

Insert the new section in `body`, after the `Section("Look-forward window")` block and before `Section("General")`:

```swift
            Section("Event Filters") {
                Toggle("Include all-day events", isOn: Binding(
                    get: { settings.includeAllDayEvents },
                    set: { settings.includeAllDayEvents = $0 }
                ))

                Toggle("Filter by work hours", isOn: Binding(
                    get: { settings.workHoursEnabled },
                    set: { settings.workHoursEnabled = $0 }
                ))

                if settings.workHoursEnabled {
                    HStack {
                        Text("From")
                        Picker("From", selection: Binding(
                            get: { settings.workHoursStart },
                            set: { newStart in
                                settings.workHoursStart = newStart
                                if settings.workHoursEnd <= newStart {
                                    settings.workHoursEnd = newStart + 1
                                }
                            }
                        )) {
                            ForEach(0..<23) { hour in
                                Text(hourLabel(hour)).tag(hour)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 110)

                        Text("to")

                        Picker("To", selection: Binding(
                            get: { settings.workHoursEnd },
                            set: { settings.workHoursEnd = $0 }
                        )) {
                            ForEach((settings.workHoursStart + 1)..<24) { hour in
                                Text(hourLabel(hour)).tag(hour)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 110)
                    }
                }
            }
```

- [ ] **Step 2: Build to confirm no compile errors**

```bash
make build 2>&1 | grep -E "(error:|BUILD SUCCEEDED|BUILD FAILED)"
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Commit**

```bash
git add CalendarCloak/UI/SettingsView.swift
git commit -m "feat: add Event Filters section to Settings (all-day toggle, work hours)"
```

---

### Task 6: Update README

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Add the two new settings entries under the Settings section**

In `README.md`, after the "Look-forward window" entry and before "Launch at login":

```markdown
**Include all-day events** — whether all-day events are mirrored as Busy blocks. On by default; turn off if you don't want full-day entries (e.g. holidays or out-of-office markers) to appear as Busy in your other calendars.

**Work hours filter** — when enabled, only events that start within the configured time window are mirrored. Use this to avoid creating Busy blocks for early-morning or late-evening events that don't affect your working day.
```

- [ ] **Step 2: Build to confirm nothing is broken**

```bash
make build 2>&1 | grep -E "(error:|BUILD SUCCEEDED|BUILD FAILED)"
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: document event filter settings in README"
```

---

## Self-Review

**Spec coverage check:**

| Spec requirement | Task |
|-----------------|------|
| Rename `bee-busy:source=` → `calendarcloak:source=` | Task 1 |
| `isLegacyBusyEvent` helper | Task 1 |
| `includeAllDayEvents` setting (default true) | Task 2 |
| `workHoursEnabled` setting (default false) | Task 2 |
| `workHoursStart` setting (default 9) | Task 2 |
| `workHoursEnd` setting (default 18) | Task 2 |
| All-day filter in EventEligibility | Task 3 |
| Work-hours filter in EventEligibility | Task 3 |
| Filter applies to both individual + series events | Task 3 — filter runs on each CalendarEvent before anchor selection in Reconciliation |
| `deleteLegacyBusyEvents()` on SyncEngine | Task 4 |
| Called before `engine.start()` in AppCoordinator | Task 4 |
| Event Filters section in SettingsView | Task 5 |
| README updated | Task 6 |

All spec requirements covered. No placeholders. Type and method names are consistent across all tasks.
