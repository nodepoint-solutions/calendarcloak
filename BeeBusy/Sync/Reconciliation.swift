import Foundation

func reconcile(
    eligibleSources: [CalendarEvent],
    busyEvents: [CalendarEvent],
    configuredCalendarIDs: [String],
    windowEnd: Date = .distantFuture
) -> [ReconciliationOperation] {
    var ops: [ReconciliationOperation] = []

    // --- Partition sources: individual vs recurring series ---

    var seriesAnchors: [String: CalendarEvent] = [:]  // seriesID -> earliest occurrence in window
    var individualSources: [CalendarEvent] = []

    for source in eligibleSources {
        if source.isRecurring {
            // All occurrences of a series share the same id (calendarItemIdentifier).
            // Keep only the earliest occurrence as the anchor for creating the Busy series.
            if let existing = seriesAnchors[source.id] {
                if source.startDate < existing.startDate { seriesAnchors[source.id] = source }
            } else {
                seriesAnchors[source.id] = source
            }
        } else {
            individualSources.append(source)
        }
    }

    // --- Partition busy events: individual vs recurring series ---

    // For series busy events: sourceID -> calendarID -> earliest occurrence (used for delete span)
    var seriesBusy: [String: [String: CalendarEvent]] = [:]
    var individualBusy: [String: [CalendarEvent]] = [:]  // sourceID -> [CalendarEvent]

    for busy in busyEvents {
        guard let sid = BusyEventMarker.sourceID(from: busy.notes) else { continue }
        if busy.isRecurring {
            if seriesBusy[sid] == nil { seriesBusy[sid] = [:] }
            let existing = seriesBusy[sid]![busy.calendarID]
            if existing == nil || busy.startDate < existing!.startDate {
                seriesBusy[sid]![busy.calendarID] = busy
            }
        } else {
            individualBusy[sid, default: []].append(busy)
        }
    }

    // --- Reconcile individual events (existing logic) ---

    let individualSourceIDs = Set(individualSources.map(\.id))

    for source in individualSources {
        let existing = individualBusy[source.id] ?? []
        let existingByCalID = Dictionary(uniqueKeysWithValues: existing.map { ($0.calendarID, $0) })
        let targetCalIDs = configuredCalendarIDs.filter { $0 != source.calendarID }

        for calID in targetCalIDs {
            if let existingBusy = existingByCalID[calID] {
                let datesChanged = existingBusy.startDate != source.startDate
                    || existingBusy.endDate != source.endDate
                    || existingBusy.isAllDay != source.isAllDay
                if datesChanged {
                    ops.append(.delete(existingBusy))
                    ops.append(.create(BusyEventDraft(calendarID: calID, startDate: source.startDate,
                                                      endDate: source.endDate, isAllDay: source.isAllDay,
                                                      sourceID: source.id)))
                }
            } else {
                ops.append(.create(BusyEventDraft(calendarID: calID, startDate: source.startDate,
                                                  endDate: source.endDate, isAllDay: source.isAllDay,
                                                  sourceID: source.id)))
            }
        }

        let targetSet = Set(targetCalIDs)
        for busy in existing where !targetSet.contains(busy.calendarID) {
            ops.append(.delete(busy))
        }
    }

    // Orphan cleanup for individual events
    for (sid, events) in individualBusy where !individualSourceIDs.contains(sid) {
        ops.append(contentsOf: events.map { .delete($0) })
    }

    // --- Reconcile recurring series (one Busy series per target calendar) ---

    for (seriesID, anchor) in seriesAnchors {
        let targetCalIDs = configuredCalendarIDs.filter { $0 != anchor.calendarID }

        for calID in targetCalIDs {
            if let existingBusy = seriesBusy[seriesID]?[calID] {
                let timingChanged = existingBusy.startDate != anchor.startDate
                    || existingBusy.endDate != anchor.endDate
                    || existingBusy.isAllDay != anchor.isAllDay
                // Cap is stale when the Busy series ends before the current window end,
                // meaning new occurrences have appeared that aren't yet covered.
                let capStale = (existingBusy.seriesEndDate ?? .distantPast) < windowEnd
                if timingChanged || capStale {
                    ops.append(.delete(existingBusy))
                    ops.append(.create(BusyEventDraft(calendarID: calID, startDate: anchor.startDate,
                                                      endDate: anchor.endDate, isAllDay: anchor.isAllDay,
                                                      sourceID: seriesID, recurrenceCapDate: windowEnd)))
                }
            } else {
                ops.append(.create(BusyEventDraft(calendarID: calID, startDate: anchor.startDate,
                                                  endDate: anchor.endDate, isAllDay: anchor.isAllDay,
                                                  sourceID: seriesID, recurrenceCapDate: windowEnd)))
            }
        }

        let targetSet = Set(targetCalIDs)
        if let calMap = seriesBusy[seriesID] {
            for (calID, busy) in calMap where !targetSet.contains(calID) {
                ops.append(.delete(busy))
            }
        }
    }

    // Orphan cleanup for series
    let seriesSourceIDs = Set(seriesAnchors.keys)
    for (sid, calMap) in seriesBusy where !seriesSourceIDs.contains(sid) {
        ops.append(contentsOf: calMap.values.map { .delete($0) })
    }

    return ops
}
