import XCTest
@testable import BeeBusy

final class EventEligibilityTests: XCTestCase {

    private func makeEvent(isAccepted: Bool, notes: String? = nil) -> CalendarEvent {
        CalendarEvent(
            id: UUID().uuidString, calendarID: "cal1", calendarName: "Work",
            title: "Meeting", startDate: Date(), endDate: Date().addingTimeInterval(3600),
            isAllDay: false, notes: notes, isAccepted: isAccepted
        )
    }

    func test_acceptedEvent_isEligible() {
        XCTAssertTrue(EventEligibility.isEligible(makeEvent(isAccepted: true)))
    }

    func test_notAcceptedEvent_isNotEligible() {
        XCTAssertFalse(EventEligibility.isEligible(makeEvent(isAccepted: false)))
    }

    func test_busyEventWithMarker_isNotEligible() {
        let busyEvent = makeEvent(isAccepted: true, notes: "bee-busy:source=abc123")
        XCTAssertFalse(EventEligibility.isEligible(busyEvent))
    }
}
