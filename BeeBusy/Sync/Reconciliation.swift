import Foundation

func reconcile(
    eligibleSources: [CalendarEvent],
    busyEvents: [CalendarEvent],
    configuredCalendarIDs: [String],
    windowEnd: Date = .distantFuture,
    logger: Logger? = nil
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

    // For series busy events: sourceID -> calendarID -> all series (may be >1 due to accumulated incomplete deletes)
    var seriesBusy: [String: [String: [CalendarEvent]]] = [:]
    var individualBusy: [String: [CalendarEvent]] = [:]  // sourceID -> [CalendarEvent]

    for busy in busyEvents {
        guard let sid = BusyEventMarker.sourceID(from: busy.notes) else { continue }
        if busy.isRecurring {
            // store.events(matching:) returns one EKEvent per occurrence; all occurrences of the same
            // series share the same calendarItemIdentifier. Deduplicate by id, keeping the earliest
            // occurrence so the startDate comparison in reconciliation matches the source anchor.
            var calMap = seriesBusy[sid, default: [:]]
            var seriesList = calMap[busy.calendarID, default: []]
            if let idx = seriesList.firstIndex(where: { $0.id == busy.id }) {
                if busy.startDate < seriesList[idx].startDate { seriesList[idx] = busy }
            } else {
                seriesList.append(busy)
            }
            calMap[busy.calendarID] = seriesList
            seriesBusy[sid] = calMap
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
            let existingList = seriesBusy[seriesID]?[calID] ?? []

            if existingList.count > 1 {
                // Multiple busy series accumulated from incomplete prior deletions — purge all and recreate clean
                logger?.debug("series \(seriesID.prefix(8)) cal=\(calID.prefix(8)): count=\(existingList.count) ids=\(existingList.map { $0.id.prefix(8) }.joined(separator: ",")) — purge+recreate")
                existingList.forEach { ops.append(.delete($0)) }
                ops.append(.create(BusyEventDraft(calendarID: calID, startDate: anchor.startDate,
                                                  endDate: anchor.endDate, isAllDay: anchor.isAllDay,
                                                  sourceID: seriesID, recurrenceCapDate: windowEnd)))
            } else if let existingBusy = existingList.first {
                let timingChanged = existingBusy.startDate != anchor.startDate
                    || existingBusy.endDate != anchor.endDate
                    || existingBusy.isAllDay != anchor.isAllDay
                // Cap is stale when the Busy series ends before the effective cap — the
                // lesser of the source's own end and windowEnd. Using raw windowEnd would
                // always fire as stale when the source ends before the window.
                let effectiveCap = anchor.seriesEndDate.map { min($0, windowEnd) } ?? windowEnd
                let capStale = (existingBusy.seriesEndDate ?? .distantPast) < effectiveCap
                if timingChanged || capStale {
                    logger?.debug("series \(seriesID.prefix(8)) cal=\(calID.prefix(8)): timingChanged=\(timingChanged) capStale=\(capStale) seriesEnd=\(existingBusy.seriesEndDate?.description ?? "nil") windowEnd=\(windowEnd) anchorStart=\(anchor.startDate) busyStart=\(existingBusy.startDate) anchorEnd=\(anchor.endDate) busyEnd=\(existingBusy.endDate)")
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
            for (calID, events) in calMap where !targetSet.contains(calID) {
                events.forEach { ops.append(.delete($0)) }
            }
        }
    }

    // Orphan cleanup for series
    let seriesSourceIDs = Set(seriesAnchors.keys)
    for (sid, calMap) in seriesBusy where !seriesSourceIDs.contains(sid) {
        for (_, events) in calMap {
            ops.append(contentsOf: events.map { .delete($0) })
        }
    }

    return ops
}
