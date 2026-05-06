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
        let settings = makeSettings(workHoursEnabled: true, workHoursStart: 9, workHoursEnd: 18)
        let start = dateWithHour(18)
        XCTAssertFalse(EventEligibility.isEligible(makeEvent(isAccepted: true, startDate: start), settings: settings))
    }

    func test_timedEvent_workHoursDisabled_ignoredByHoursCheck() {
        let settings = makeSettings(workHoursEnabled: false, workHoursStart: 9, workHoursEnd: 18)
        let start = dateWithHour(7)
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
