import EventKit
import Foundation

protocol CalendarStoreProtocol: AnyObject {
    func requestAccess() async throws
    func fetchCalendars() -> [EKCalendar]
    func fetchEvents(calendarIDs: [String], start: Date, end: Date) -> [CalendarEvent]
    func create(_ draft: BusyEventDraft) throws
    func delete(_ event: CalendarEvent)
}

final class EventKitStore: CalendarStoreProtocol {
    private let store = EKEventStore()
    private let logger: Logger
    private var ekEventCache: [String: EKEvent] = [:]

    init(logger: Logger) {
        self.logger = logger
    }

    func requestAccess() async throws {
        try await store.requestFullAccessToEvents()
    }

    func fetchCalendars() -> [EKCalendar] {
        store.calendars(for: .event)
    }

    func fetchEvents(calendarIDs: [String], start: Date, end: Date) -> [CalendarEvent] {
        let calendars = store.calendars(for: .event).filter { calendarIDs.contains($0.calendarIdentifier) }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
        let ekEvents = store.events(matching: predicate)
        ekEventCache.removeAll()
        return ekEvents.compactMap { ekEvent -> CalendarEvent? in
            guard let cal = ekEvent.calendar else { return nil }
            ekEventCache[ekEvent.calendarItemIdentifier] = ekEvent
            return CalendarEvent(
                id: ekEvent.calendarItemIdentifier,
                calendarID: cal.calendarIdentifier,
                calendarName: cal.title,
                title: ekEvent.title ?? "",
                startDate: ekEvent.startDate,
                endDate: ekEvent.endDate,
                isAllDay: ekEvent.isAllDay,
                notes: ekEvent.notes,
                isAccepted: resolveAcceptance(ekEvent)
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
        try store.save(event, span: .thisEvent, commit: true)
        logger.info("Created Busy event in \(calendar.title) for source \(draft.sourceID)")
    }

    func delete(_ event: CalendarEvent) {
        // SAFETY GUARD: abort if this is not one of our managed Busy events
        guard BusyEventMarker.sourceID(from: event.notes) != nil else {
            logger.error("SAFETY: attempted to delete non-bee-busy event \(event.id) — aborted")
            return
        }
        let ekEvent = ekEventCache[event.id]
            ?? (store.calendarItem(withIdentifier: event.id) as? EKEvent)
        guard let ekEvent else {
            logger.warn("Could not find EKEvent for \(event.id) — already deleted?")
            return
        }
        do {
            try store.remove(ekEvent, span: .thisEvent, commit: true)
            logger.info("Deleted Busy event \(event.id)")
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
}
