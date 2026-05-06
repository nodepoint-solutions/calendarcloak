# Cleanup Feature Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a "Delete All Busy Events" button to the Settings screen that removes every bee-busy-managed event across all calendars using the existing safeguarded delete function.

**Architecture:** Extend `CalendarStoreProtocol` with `fetchAllCalendarIDs()` to avoid EKCalendar dependencies in the sync layer; add `deleteAllBusyEvents()` to `SyncEngine` that fetches all calendar IDs, fetches events, filters by `BusyEventMarker.isBusyEvent`, and deletes via the safeguarded `store.delete(_:)`; add a destructive button + confirmation dialog to `SettingsView`.

**Tech Stack:** Swift, SwiftUI, EventKit, XCTest

---

## File Map

| File | Change |
|------|--------|
| `BeeBusy/EventKit/EventKitStore.swift` | Add `fetchAllCalendarIDs()` to protocol + implementation |
| `BeeBusyTests/Mocks/MockCalendarStore.swift` | Add `stubbedCalendarIDs` + `fetchAllCalendarIDs()` |
| `BeeBusy/Sync/SyncEngine.swift` | Add `deleteAllBusyEvents()` |
| `BeeBusyTests/SyncEngineTests.swift` | New — tests for `deleteAllBusyEvents()` |
| `BeeBusy/UI/SettingsView.swift` | Add cleanup button + confirmation dialog |

---

### Task 1: Extend protocol and store with `fetchAllCalendarIDs()`

**Files:**
- Modify: `BeeBusy/EventKit/EventKitStore.swift`
- Modify: `BeeBusyTests/Mocks/MockCalendarStore.swift`

- [ ] **Step 1: Add `fetchAllCalendarIDs()` to `CalendarStoreProtocol`**

In `BeeBusy/EventKit/EventKitStore.swift`, add one line to the protocol:

```swift
protocol CalendarStoreProtocol: AnyObject {
    func requestAccess() async throws
    func fetchCalendars() -> [EKCalendar]
    func fetchAllCalendarIDs() -> [String]        // ← add this line
    func fetchEvents(calendarIDs: [String], start: Date, end: Date) -> [CalendarEvent]
    func create(_ draft: BusyEventDraft) throws
    func delete(_ event: CalendarEvent)
}
```

- [ ] **Step 2: Implement `fetchAllCalendarIDs()` in `EventKitStore`**

Add this method to `EventKitStore`, after `fetchCalendars()`:

```swift
func fetchAllCalendarIDs() -> [String] {
    store.calendars(for: .event)
        .filter { $0.allowsContentModifications }
        .map { $0.calendarIdentifier }
}
```

- [ ] **Step 3: Add stub to `MockCalendarStore`**

In `BeeBusyTests/Mocks/MockCalendarStore.swift`, add a property and implement the protocol method:

```swift
final class MockCalendarStore: CalendarStoreProtocol {
    var stubbedCalendars: [EKCalendar] = []
    var stubbedCalendarIDs: [String] = []        // ← add this property
    var stubbedEvents: [CalendarEvent] = []
    var createdDrafts: [BusyEventDraft] = []
    var deletedEvents: [CalendarEvent] = []
    var requestAccessError: Error? = nil

    func requestAccess() async throws {
        if let error = requestAccessError { throw error }
    }

    func fetchCalendars() -> [EKCalendar] {
        stubbedCalendars
    }

    func fetchAllCalendarIDs() -> [String] {     // ← add this method
        stubbedCalendarIDs
    }

    func fetchEvents(calendarIDs: [String], start: Date, end: Date) -> [CalendarEvent] {
        stubbedEvents.filter { calendarIDs.contains($0.calendarID) }
    }

    func create(_ draft: BusyEventDraft) throws {
        createdDrafts.append(draft)
    }

    func delete(_ event: CalendarEvent) {
        deletedEvents.append(event)
    }
}
```

- [ ] **Step 4: Build to confirm no compile errors**

```bash
xcodebuild build -scheme BeeBusy -destination 'platform=macOS' 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add BeeBusy/EventKit/EventKitStore.swift BeeBusyTests/Mocks/MockCalendarStore.swift
git commit -m "feat: add fetchAllCalendarIDs to CalendarStoreProtocol"
```

---

### Task 2: Add `deleteAllBusyEvents()` to `SyncEngine` — TDD

**Files:**
- Create: `BeeBusyTests/SyncEngineTests.swift`
- Modify: `BeeBusy/Sync/SyncEngine.swift`

- [ ] **Step 1: Create the test file**

Create `BeeBusyTests/SyncEngineTests.swift`:

```swift
import XCTest
@testable import BeeBusy

@MainActor
final class SyncEngineTests: XCTestCase {

    private func makeEngine(store: MockCalendarStore) -> SyncEngine {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(30, forKey: "lookForwardDays")
        let settings = AppSettings(defaults: defaults)
        return SyncEngine(store: store, settings: settings, state: AppState(), logger: Logger())
    }

    private func busyEvent(id: String, calendarID: String) -> CalendarEvent {
        CalendarEvent(id: id, calendarID: calendarID, calendarName: calendarID,
                      title: "Busy", startDate: Date(), endDate: Date().addingTimeInterval(3600),
                      isAllDay: false, notes: BusyEventMarker.notes(for: "src-\(id)"), isAccepted: true)
    }

    private func sourceEvent(id: String, calendarID: String) -> CalendarEvent {
        CalendarEvent(id: id, calendarID: calendarID, calendarName: calendarID,
                      title: "Meeting", startDate: Date(), endDate: Date().addingTimeInterval(3600),
                      isAllDay: false, notes: nil, isAccepted: true)
    }

    func test_deleteAllBusyEvents_deletesBusyEventsAcrossAllCalendars() {
        let store = MockCalendarStore()
        store.stubbedCalendarIDs = ["calA", "calB"]
        store.stubbedEvents = [
            busyEvent(id: "b1", calendarID: "calA"),
            busyEvent(id: "b2", calendarID: "calB"),
        ]
        let engine = makeEngine(store: store)

        engine.deleteAllBusyEvents()

        XCTAssertEqual(store.deletedEvents.count, 2)
        XCTAssertTrue(store.deletedEvents.contains { $0.id == "b1" })
        XCTAssertTrue(store.deletedEvents.contains { $0.id == "b2" })
    }

    func test_deleteAllBusyEvents_doesNotDeleteSourceEvents() {
        let store = MockCalendarStore()
        store.stubbedCalendarIDs = ["calA"]
        store.stubbedEvents = [
            busyEvent(id: "b1", calendarID: "calA"),
            sourceEvent(id: "s1", calendarID: "calA"),
        ]
        let engine = makeEngine(store: store)

        engine.deleteAllBusyEvents()

        XCTAssertEqual(store.deletedEvents.count, 1)
        XCTAssertEqual(store.deletedEvents.first?.id, "b1")
    }

    func test_deleteAllBusyEvents_noEventsIsNoop() {
        let store = MockCalendarStore()
        store.stubbedCalendarIDs = ["calA"]
        store.stubbedEvents = []
        let engine = makeEngine(store: store)

        engine.deleteAllBusyEvents()

        XCTAssertTrue(store.deletedEvents.isEmpty)
    }

    func test_deleteAllBusyEvents_noCalendarsIsNoop() {
        let store = MockCalendarStore()
        store.stubbedCalendarIDs = []
        store.stubbedEvents = [busyEvent(id: "b1", calendarID: "calA")]
        let engine = makeEngine(store: store)

        engine.deleteAllBusyEvents()

        XCTAssertTrue(store.deletedEvents.isEmpty)
    }
}
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
xcodebuild test -scheme BeeBusy -destination 'platform=macOS' -only-testing BeeBusyTests/SyncEngineTests 2>&1 | grep -E "error:|FAILED|passed|failed"
```
Expected: compile error — `'SyncEngine' has no member 'deleteAllBusyEvents'`

- [ ] **Step 3: Implement `deleteAllBusyEvents()` in `SyncEngine`**

In `BeeBusy/Sync/SyncEngine.swift`, add this method after `cleanupRemovedCalendar`:

```swift
func deleteAllBusyEvents() {
    let calendarIDs = store.fetchAllCalendarIDs()
    guard !calendarIDs.isEmpty else { return }
    let window = lookForwardWindow()
    let events = store.fetchEvents(calendarIDs: calendarIDs, start: window.start, end: window.end)
    let busyToDelete = events.filter { BusyEventMarker.isBusyEvent($0) }
    logger.info("Deleting \(busyToDelete.count) Busy events across all calendars")
    for event in busyToDelete {
        store.delete(event)
    }
    logger.info("Cleanup complete")
}
```

- [ ] **Step 4: Run tests to confirm they pass**

```bash
xcodebuild test -scheme BeeBusy -destination 'platform=macOS' -only-testing BeeBusyTests/SyncEngineTests 2>&1 | grep -E "error:|FAILED|passed|failed"
```
Expected: `Test Suite 'SyncEngineTests' passed` / `4 tests passed`

- [ ] **Step 5: Run full test suite to confirm no regressions**

```bash
xcodebuild test -scheme BeeBusy -destination 'platform=macOS' 2>&1 | grep -E "error:|FAILED|passed|failed" | tail -10
```
Expected: all tests pass, no failures.

- [ ] **Step 6: Commit**

```bash
git add BeeBusyTests/SyncEngineTests.swift BeeBusy/Sync/SyncEngine.swift
git commit -m "feat: add deleteAllBusyEvents to SyncEngine"
```

---

### Task 3: Add cleanup button and confirmation dialog to `SettingsView`

**Files:**
- Modify: `BeeBusy/UI/SettingsView.swift`

No automated UI test — verify manually after implementation.

- [ ] **Step 1: Add state property for confirmation dialog**

In `BeeBusy/UI/SettingsView.swift`, add a `@State` property for the confirmation dialog after the existing `@State private var calendars` declaration:

```swift
struct SettingsView: View {
    @State private var calendars: [EKCalendar] = []
    @State private var showingCleanupConfirmation = false   // ← add this
    let settings: AppSettings
    let store: CalendarStoreProtocol
    let logger: Logger
    let engine: SyncEngine
```

- [ ] **Step 2: Add the cleanup button to the General section**

Replace the existing General section:

```swift
Section("General") {
    Toggle("Launch at login", isOn: Binding(
        get: { settings.launchAtLogin },
        set: { newValue in
            settings.launchAtLogin = newValue
            applyLaunchAtLogin(newValue)
        }
    ))

    Button("View Logs") {
        let logsURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("Logs/BeeBusy/bee-busy.log")
        NSWorkspace.shared.open(logsURL)
    }

    Button("Delete All Busy Events…") {
        showingCleanupConfirmation = true
    }
    .foregroundStyle(.red)
}
```

- [ ] **Step 3: Attach the confirmation dialog to the Form**

Add the `.confirmationDialog` modifier to the `Form`, after `.onAppear`:

```swift
.onAppear { calendars = store.fetchCalendars() }
.confirmationDialog(
    "Delete All Busy Events?",
    isPresented: $showingCleanupConfirmation,
    titleVisibility: .visible
) {
    Button("Delete", role: .destructive) {
        engine.deleteAllBusyEvents()
    }
    Button("Cancel", role: .cancel) {}
} message: {
    Text("This will remove all Busy events from all calendars. This cannot be undone.")
}
```

- [ ] **Step 4: Build to confirm no compile errors**

```bash
xcodebuild build -scheme BeeBusy -destination 'platform=macOS' 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Manually verify the UI**
  - Launch the app
  - Open Settings
  - Confirm "Delete All Busy Events…" appears in the General section in red
  - Tap it — confirm the dialog appears with the correct title, message, and a red "Delete" button
  - Tap Cancel — confirm nothing happens
  - (Optional) Tap Delete — confirm Busy events are removed and the engine recreates them on next sync

- [ ] **Step 6: Commit**

```bash
git add BeeBusy/UI/SettingsView.swift
git commit -m "feat: add Delete All Busy Events button to Settings"
```
