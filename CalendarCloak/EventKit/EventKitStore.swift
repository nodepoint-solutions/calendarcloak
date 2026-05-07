import EventKit
import Foundation

protocol CalendarStoreProtocol: AnyObject {
    func requestAccess() async throws
    func fetchCalendars() -> [EKCalendar]
    func fetchAllCalendarIDs() -> [String]
    func fetchEvents(calendarIDs: [String], start: Date, end: Date) -> [CalendarEvent]
    func create(_ draft: BusyEventDraft) throws
    func delete(_ event: CalendarEvent)
}

final class EventKitStore: CalendarStoreProtocol {
    private let store = EKEventStore()
    private let logger: Logger
    // Keyed by calendarItemIdentifier. For recurring series all occurrences share the same key;
    // the last one written wins, which is fine since any occurrence carries the same recurrence rules.
    private var ekEventCache: [String: EKEvent] = [:]

    init(logger: Logger) {
        self.logger = logger
    }

    func requestAccess() async throws {
        try await store.requestFullAccessToEvents()
    }

    func fetchCalendars() -> [EKCalendar] {
        store.calendars(for: .event).filter { $0.allowsContentModifications }
    }

    func fetchAllCalendarIDs() -> [String] {
        fetchCalendars().map { $0.calendarIdentifier }
    }

    func fetchEvents(calendarIDs: [String], start: Date, end: Date) -> [CalendarEvent] {
        let calendars = store.calendars(for: .event).filter { calendarIDs.contains($0.calendarIdentifier) }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
        let ekEvents = store.events(matching: predicate)
        ekEventCache.removeAll()
        return ekEvents.compactMap { ekEvent -> CalendarEvent? in
            guard let cal = ekEvent.calendar else { return nil }
            ekEventCache[ekEvent.calendarItemIdentifier] = ekEvent
            let hasRules = !(ekEvent.recurrenceRules?.isEmpty ?? true)
            return CalendarEvent(
                id: ekEvent.calendarItemIdentifier,
                calendarID: cal.calendarIdentifier,
                calendarName: cal.title,
                title: ekEvent.title ?? "",
                startDate: ekEvent.startDate,
                endDate: ekEvent.endDate,
                isAllDay: ekEvent.isAllDay,
                notes: ekEvent.notes,
                isAccepted: resolveAcceptance(ekEvent),
                isRecurring: hasRules && !ekEvent.isDetached,
                isDetached: ekEvent.isDetached,
                seriesEndDate: ekEvent.recurrenceRules?.first?.recurrenceEnd?.endDate
            )
        }
    }

    func create(_ draft: BusyEventDraft) throws {
        guard let calendar = store.calendars(for: .event)
            .first(where: { $0.calendarIdentifier == draft.calendarID }) else {
            logger.error("Cannot find calendar \(draft.calendarID) to create Busy event")
            return
        }
        let event = EKEvent(eventStore: store)
        event.title = draft.title
        event.notes = draft.notes
        event.startDate = draft.startDate
        event.endDate = draft.endDate
        event.isAllDay = draft.isAllDay
        event.calendar = calendar
        event.alarms = nil

        if let capDate = draft.recurrenceCapDate,
           let sourceRules = ekEventCache[draft.sourceID]?.recurrenceRules,
           !sourceRules.isEmpty {
            event.recurrenceRules = sourceRules.map { cappedRule($0, cap: capDate) }
            logger.info("Creating recurring Busy series in \(calendar.title) for source \(draft.sourceID) capped to \(capDate)")
        }

        try store.save(event, span: .thisEvent, commit: true)
        logger.info("Created Busy event in \(calendar.title) for source \(draft.sourceID)")
    }

    func delete(_ event: CalendarEvent) {
        // SAFETY GUARD: abort if this is not one of our managed Busy events
        guard BusyEventMarker.sourceID(from: event.notes) != nil else {
            logger.error("SAFETY: attempted to delete non-managed event \(event.id) — aborted")
            return
        }
        // For recurring series, bypass the occurrence cache (which holds the last fetched occurrence)
        // and use calendarItem(withIdentifier:) to get the master event. Removing the master with
        // .futureEvents deletes the entire series; removing a later cached occurrence would only
        // remove that tail, leaving earlier occurrences stranded and accumulating across syncs.
        let ekEvent: EKEvent?
        if event.isRecurring {
            ekEvent = store.calendarItem(withIdentifier: event.id) as? EKEvent
        } else {
            ekEvent = ekEventCache[event.id]
                ?? (store.calendarItem(withIdentifier: event.id) as? EKEvent)
        }
        guard let ekEvent else {
            logger.warn("Could not find EKEvent for \(event.id) — already deleted?")
            return
        }
        do {
            let span: EKSpan = event.isRecurring ? .futureEvents : .thisEvent
            try store.remove(ekEvent, span: span, commit: true)
            logger.info("Deleted Busy event \(event.id) (recurring: \(event.isRecurring))")
        } catch {
            logger.error("Failed to delete Busy event \(event.id): \(error)")
        }
    }

    // MARK: - Private

    private func resolveAcceptance(_ ekEvent: EKEvent) -> Bool {
        guard let attendees = ekEvent.attendees, !attendees.isEmpty else {
            return true  // self-created event, no attendees
        }
        return attendees.first(where: { $0.isCurrentUser })?.participantStatus == .accepted
    }

    private func cappedRule(_ rule: EKRecurrenceRule, cap: Date) -> EKRecurrenceRule {
        // Honour the source series' own end date if it falls before our window cap.
        let effectiveCap: Date
        if let sourceEnd = rule.recurrenceEnd?.endDate {
            effectiveCap = min(sourceEnd, cap)
        } else {
            effectiveCap = cap
        }
        return EKRecurrenceRule(
            recurrenceWith: rule.frequency,
            interval: rule.interval,
            daysOfTheWeek: rule.daysOfTheWeek,
            daysOfTheMonth: rule.daysOfTheMonth,
            monthsOfTheYear: rule.monthsOfTheYear,
            weeksOfTheYear: rule.weeksOfTheYear,
            daysOfTheYear: rule.daysOfTheYear,
            setPositions: rule.setPositions,
            end: EKRecurrenceEnd(end: effectiveCap)
        )
    }
}
