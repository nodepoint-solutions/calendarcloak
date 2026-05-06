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

    // MARK: - Recurring series

    private func recurringSource(id: String, cal: String, start: Date, end: Date,
                                 seriesEndDate: Date? = nil) -> CalendarEvent {
        CalendarEvent(id: id, calendarID: cal, calendarName: cal,
                      title: "Standup", startDate: start, endDate: end,
                      isAllDay: false, notes: nil, isAccepted: true,
                      isRecurring: true, isDetached: false, seriesEndDate: seriesEndDate)
    }

    private func recurringBusy(sourceID: String, cal: String, start: Date, end: Date,
                               seriesEndDate: Date?) -> CalendarEvent {
        CalendarEvent(id: UUID().uuidString, calendarID: cal, calendarName: cal,
                      title: "Busy", startDate: start, endDate: end,
                      isAllDay: false, notes: BusyEventMarker.notes(for: sourceID), isAccepted: true,
                      isRecurring: true, isDetached: false, seriesEndDate: seriesEndDate)
    }

    private let windowEnd = Date().addingTimeInterval(30 * 86400)

    func test_recurringSeries_createsSingleBusySeriesPerTargetCalendar() {
        // Three occurrences of the same series in the window — should produce ONE create per target, not three
        let occ1 = recurringSource(id: "series1", cal: calA, start: now, end: now.addingTimeInterval(3600))
        let occ2 = recurringSource(id: "series1", cal: calA, start: now.addingTimeInterval(7 * 86400), end: now.addingTimeInterval(7 * 86400 + 3600))
        let occ3 = recurringSource(id: "series1", cal: calA, start: now.addingTimeInterval(14 * 86400), end: now.addingTimeInterval(14 * 86400 + 3600))
        let ops = reconcile(eligibleSources: [occ1, occ2, occ3], busyEvents: [],
                            configuredCalendarIDs: [calA, calB, calC], windowEnd: windowEnd)
        // ONE create per target calendar (not 3 × 2 = 6)
        XCTAssertEqual(ops.count, 2)
        let creates = ops.compactMap { if case .create(let d) = $0 { return d } else { return nil } }
        XCTAssertTrue(creates.allSatisfy { $0.recurrenceCapDate == windowEnd })
        XCTAssertTrue(creates.allSatisfy { $0.startDate == now })  // anchor = earliest occurrence
    }

    func test_recurringSeries_noOpWhenBusySeriesUpToDate() {
        let src = recurringSource(id: "series1", cal: calA, start: now, end: now.addingTimeInterval(3600))
        let existingB = recurringBusy(sourceID: "series1", cal: calB, start: now,
                                      end: now.addingTimeInterval(3600), seriesEndDate: windowEnd)
        let existingC = recurringBusy(sourceID: "series1", cal: calC, start: now,
                                      end: now.addingTimeInterval(3600), seriesEndDate: windowEnd)
        let ops = reconcile(eligibleSources: [src], busyEvents: [existingB, existingC],
                            configuredCalendarIDs: [calA, calB, calC], windowEnd: windowEnd)
        XCTAssertEqual(ops.count, 0)
    }

    func test_recurringSeries_recreatesWhenCapIsStale() {
        let src = recurringSource(id: "series1", cal: calA, start: now, end: now.addingTimeInterval(3600))
        let staleEnd = now.addingTimeInterval(10 * 86400)  // cap was 10 days, window is now 30 days
        let existingB = recurringBusy(sourceID: "series1", cal: calB, start: now,
                                      end: now.addingTimeInterval(3600), seriesEndDate: staleEnd)
        let ops = reconcile(eligibleSources: [src], busyEvents: [existingB],
                            configuredCalendarIDs: [calA, calB], windowEnd: windowEnd)
        XCTAssertTrue(ops.contains(.delete(existingB)))
        let creates = ops.compactMap { if case .create(let d) = $0 { return d } else { return nil } }
        XCTAssertTrue(creates.contains { $0.calendarID == calB && $0.recurrenceCapDate == windowEnd })
    }

    func test_detachedOccurrence_treatedAsIndividualEvent() {
        // A detached occurrence (isDetached=true) should be handled individually, not as part of a series
        let detached = CalendarEvent(id: "detached-unique-id", calendarID: calA, calendarName: calA,
                                     title: "Standup (moved)", startDate: now, endDate: now.addingTimeInterval(3600),
                                     isAllDay: false, notes: nil, isAccepted: true,
                                     isRecurring: false, isDetached: true, seriesEndDate: nil)
        let ops = reconcile(eligibleSources: [detached], busyEvents: [],
                            configuredCalendarIDs: [calA, calB], windowEnd: windowEnd)
        let creates = ops.compactMap { if case .create(let d) = $0 { return d } else { return nil } }
        // Individual event — no recurrenceCapDate
        XCTAssertTrue(creates.allSatisfy { $0.recurrenceCapDate == nil })
        XCTAssertEqual(creates.count, 1)
    }

    // MARK: - Accumulated duplicate series cleanup

    func test_multipleBusySeriesForSameSource_deletesAllAndRecreates() {
        // Simulates state after Bug: incomplete deletions left multiple partial busy series
        // for the same (sourceID, calID) pair
        let src = recurringSource(id: "series1", cal: calA, start: now, end: now.addingTimeInterval(3600))
        let staleEnd = now.addingTimeInterval(10 * 86400)
        let busyB_old = recurringBusy(sourceID: "series1", cal: calB, start: now,
                                      end: now.addingTimeInterval(3600), seriesEndDate: staleEnd)
        let busyB_newer = recurringBusy(sourceID: "series1", cal: calB, start: now,
                                        end: now.addingTimeInterval(3600), seriesEndDate: staleEnd)

        let ops = reconcile(eligibleSources: [src], busyEvents: [busyB_old, busyB_newer],
                            configuredCalendarIDs: [calA, calB], windowEnd: windowEnd)

        XCTAssertTrue(ops.contains(.delete(busyB_old)), "must delete first duplicate")
        XCTAssertTrue(ops.contains(.delete(busyB_newer)), "must delete second duplicate")
        let creates = ops.compactMap { if case .create(let d) = $0 { return d } else { return nil } }
        XCTAssertEqual(creates.count, 1, "must recreate exactly one fresh series")
        XCTAssertEqual(creates.first?.calendarID, calB)
        XCTAssertEqual(creates.first?.recurrenceCapDate, windowEnd)
    }

    func test_multipleOrphanedBusySeries_deletesAll() {
        // Multiple accumulated busy series for a source that no longer exists
        let orphan1 = recurringBusy(sourceID: "gone", cal: calB, start: now,
                                    end: now.addingTimeInterval(3600),
                                    seriesEndDate: now.addingTimeInterval(10 * 86400))
        let orphan2 = recurringBusy(sourceID: "gone", cal: calB,
                                    start: now.addingTimeInterval(86400),
                                    end: now.addingTimeInterval(86400 + 3600),
                                    seriesEndDate: now.addingTimeInterval(20 * 86400))

        let ops = reconcile(eligibleSources: [], busyEvents: [orphan1, orphan2],
                            configuredCalendarIDs: [calA, calB], windowEnd: windowEnd)

        XCTAssertTrue(ops.contains(.delete(orphan1)), "must delete first orphan")
        XCTAssertTrue(ops.contains(.delete(orphan2)), "must delete second orphan")
        XCTAssertEqual(ops.count, 2)
    }
}
