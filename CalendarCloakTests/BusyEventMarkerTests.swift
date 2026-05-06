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
