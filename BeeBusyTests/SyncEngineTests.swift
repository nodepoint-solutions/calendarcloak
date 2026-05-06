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
