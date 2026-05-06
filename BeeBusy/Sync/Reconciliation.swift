import Foundation

func reconcile(
    eligibleSources: [CalendarEvent],
    busyEvents: [CalendarEvent],
    configuredCalendarIDs: [String]
) -> [ReconciliationOperation] {
    var operations: [ReconciliationOperation] = []

    // Build lookup: sourceID → [busyEvent per calendar]
    var busyBySourceID: [String: [CalendarEvent]] = [:]
    for busy in busyEvents {
        guard let sid = BusyEventMarker.sourceID(from: busy.notes) else { continue }
        busyBySourceID[sid, default: []].append(busy)
    }

    let sourceIDs = Set(eligibleSources.map(\.id))

    for source in eligibleSources {
        let existing = busyBySourceID[source.id] ?? []
        let existingByCalID = Dictionary(uniqueKeysWithValues: existing.map { ($0.calendarID, $0) })
        let targetCalIDs = configuredCalendarIDs.filter { $0 != source.calendarID }

        for calID in targetCalIDs {
            if let existingBusy = existingByCalID[calID] {
                let datesChanged = existingBusy.startDate != source.startDate
                    || existingBusy.endDate != source.endDate
                    || existingBusy.isAllDay != source.isAllDay
                if datesChanged {
                    operations.append(.delete(existingBusy))
                    operations.append(.create(BusyEventDraft(
                        calendarID: calID,
                        startDate: source.startDate,
                        endDate: source.endDate,
                        isAllDay: source.isAllDay,
                        sourceID: source.id
                    )))
                }
            } else {
                operations.append(.create(BusyEventDraft(
                    calendarID: calID,
                    startDate: source.startDate,
                    endDate: source.endDate,
                    isAllDay: source.isAllDay,
                    sourceID: source.id
                )))
            }
        }

        // Delete busy events in calendars no longer in the target set
        let targetSet = Set(targetCalIDs)
        for busy in existing where !targetSet.contains(busy.calendarID) {
            operations.append(.delete(busy))
        }
    }

    // Orphan cleanup: busy events whose source no longer exists in the look-forward window
    for (sid, events) in busyBySourceID where !sourceIDs.contains(sid) {
        operations.append(contentsOf: events.map { .delete($0) })
    }

    return operations
}
