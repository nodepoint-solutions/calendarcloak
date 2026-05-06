import XCTest
@testable import BeeBusy

final class ReconciliationTests: XCTestCase {

    private let calA = "calA"
    private let calB = "calB"
    private let calC = "calC"

    private func source(id: String, cal: String, start: Date, end: Date) -> CalendarEvent {
        CalendarEvent(id: id, calendarID: cal, calendarName: cal,
                      title: "Meeting", startDate: start, endDate: end,
                      isAllDay: false, notes: nil, isAccepted: true)
    }

    private func busy(sourceID: String, cal: String, start: Date, end: Date) -> CalendarEvent {
        CalendarEvent(id: UUID().uuidString, calendarID: cal, calendarName: cal,
                      title: "Busy", startDate: start, endDate: end,
                      isAllDay: false, notes: BusyEventMarker.notes(for: sourceID), isAccepted: true)
    }

    private let now = Date()

    // MARK: - Create

    func test_newSourceEvent_createsBusyInOtherCalendars() {
        let src = source(id: "src1", cal: calA, start: now, end: now.addingTimeInterval(3600))
        let ops = reconcile(eligibleSources: [src], busyEvents: [], configuredCalendarIDs: [calA, calB, calC])
        XCTAssertEqual(ops.count, 2)
        XCTAssertTrue(ops.contains(.create(BusyEventDraft(calendarID: calB, startDate: now, endDate: now.addingTimeInterval(3600), isAllDay: false, sourceID: "src1"))))
        XCTAssertTrue(ops.contains(.create(BusyEventDraft(calendarID: calC, startDate: now, endDate: now.addingTimeInterval(3600), isAllDay: false, sourceID: "src1"))))
    }

    func test_existingBusyWithSameDates_noOp() {
        let start = now, end = now.addingTimeInterval(3600)
        let src = source(id: "src1", cal: calA, start: start, end: end)
        let existingB = busy(sourceID: "src1", cal: calB, start: start, end: end)
        let existingC = busy(sourceID: "src1", cal: calC, start: start, end: end)
        let ops = reconcile(eligibleSources: [src], busyEvents: [existingB, existingC], configuredCalendarIDs: [calA, calB, calC])
        XCTAssertEqual(ops.count, 0)
    }

    // MARK: - Delete (source removed)

    func test_deletedSourceEvent_deletesOrphanedBusy() {
        let existingB = busy(sourceID: "src1", cal: calB, start: now, end: now.addingTimeInterval(3600))
        let ops = reconcile(eligibleSources: [], busyEvents: [existingB], configuredCalendarIDs: [calA, calB, calC])
        XCTAssertEqual(ops, [.delete(existingB)])
    }

    // MARK: - Update (dates changed)

    func test_modifiedSourceEvent_replacesExistingBusy() {
        let oldEnd = now.addingTimeInterval(3600)
        let newEnd = now.addingTimeInterval(7200)
        let src = source(id: "src1", cal: calA, start: now, end: newEnd)
        let staleB = busy(sourceID: "src1", cal: calB, start: now, end: oldEnd)
        let ops = reconcile(eligibleSources: [src], busyEvents: [staleB], configuredCalendarIDs: [calA, calB, calC])
        XCTAssertTrue(ops.contains(.delete(staleB)))
        XCTAssertTrue(ops.contains(.create(BusyEventDraft(calendarID: calB, startDate: now, endDate: newEnd, isAllDay: false, sourceID: "src1"))))
        XCTAssertTrue(ops.contains(.create(BusyEventDraft(calendarID: calC, startDate: now, endDate: newEnd, isAllDay: false, sourceID: "src1"))))
    }

    // MARK: - Loop guard

    func test_busyEventsAreNeverSourcesForNewBusyEvents() {
        let busyInB = busy(sourceID: "src1", cal: calB, start: now, end: now.addingTimeInterval(3600))
        let ops = reconcile(eligibleSources: [], busyEvents: [busyInB], configuredCalendarIDs: [calA, calB, calC])
        XCTAssertFalse(ops.contains(where: { if case .create(_) = $0 { return true }; return false }))
    }

    // MARK: - Multi-source

    func test_multipleSourceEvents_eachGetsBusyInOtherCalendars() {
        let srcA = source(id: "srcA", cal: calA, start: now, end: now.addingTimeInterval(3600))
        let srcB = source(id: "srcB", cal: calB, start: now, end: now.addingTimeInterval(1800))
        let ops = reconcile(eligibleSources: [srcA, srcB], busyEvents: [], configuredCalendarIDs: [calA, calB, calC])
        // srcA → calB + calC (2 creates), srcB → calA + calC (2 creates)
        XCTAssertEqual(ops.count, 4)
    }
}
