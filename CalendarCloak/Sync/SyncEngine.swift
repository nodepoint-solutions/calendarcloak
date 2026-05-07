import Foundation
import EventKit

@MainActor
final class SyncEngine {
    private let store: CalendarStoreProtocol
    private let settings: AppSettings
    private let state: AppState
    private let logger: Logger

    private var notificationObserver: NSObjectProtocol?
    private var debounceTask: Task<Void, Never>?

    init(store: CalendarStoreProtocol, settings: AppSettings, state: AppState, logger: Logger) {
        self.store = store
        self.settings = settings
        self.state = state
        self.logger = logger
    }

    func start() {
        subscribeToChanges()
        Task { await runReconciliation() }
    }

    func stop() {
        debounceTask?.cancel()
        if let observer = notificationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func cleanupRemovedCalendar(id calendarID: String) {
        logger.info("Cleaning up Busy events in removed calendar \(calendarID)")
        let window = lookForwardWindow()
        let events = store.fetchEvents(calendarIDs: [calendarID], start: window.start, end: window.end)
        let busyToDelete = events.filter { BusyEventMarker.isBusyEvent($0) }
        for event in busyToDelete {
            store.delete(event)
        }
        logger.info("Removed \(busyToDelete.count) Busy events from \(calendarID)")
    }

    func deleteAllBusyEventsAndReset() {
        // Stop the engine first so EKEventStoreChanged notifications fired during deletion
        // don't reschedule reconciliation and recreate events mid-sweep.
        stop()
        settings.selectedCalendarIDs = []
        settings.hasCompletedSetup = false
        state.lastSyncDate = nil
        state.activeCalendarNames = []

        let calendarIDs = store.fetchAllCalendarIDs()
        guard !calendarIDs.isEmpty else {
            logger.info("No calendars found during factory reset sweep")
            return
        }

        // .distantPast / .distantFuture cause EventKit's predicate to return empty results.
        // EventKit enforces a ~4-year maximum span per predicate, so sweep in two chunks.
        // Deduplicate by ID in case an event falls exactly on the boundary.
        let now = Date()
        let pastStart  = Calendar.current.date(byAdding: .year, value: -4, to: now)!
        let futureEnd  = Calendar.current.date(byAdding: .year, value:  4, to: now)!
        let pastEvents   = store.fetchEvents(calendarIDs: calendarIDs, start: pastStart, end: now)
        let futureEvents = store.fetchEvents(calendarIDs: calendarIDs, start: now, end: futureEnd)

        var seenIDs = Set<String>()
        let busyToDelete = (pastEvents + futureEvents).filter { event in
            (BusyEventMarker.isBusyEvent(event) || BusyEventMarker.isLegacyBusyEvent(event))
                && seenIDs.insert(event.id).inserted
        }
        for event in busyToDelete {
            store.delete(event)
        }
        logger.info("Factory reset: deleted \(busyToDelete.count) Busy events across all calendars")
    }

    func deleteLegacyBusyEvents() {
        let calendarIDs = store.fetchAllCalendarIDs()
        guard !calendarIDs.isEmpty else { return }
        let now = Date()
        let pastStart  = Calendar.current.date(byAdding: .year, value: -4, to: now)!
        let futureEnd  = Calendar.current.date(byAdding: .year, value:  4, to: now)!
        let pastEvents   = store.fetchEvents(calendarIDs: calendarIDs, start: pastStart, end: now)
        let futureEvents = store.fetchEvents(calendarIDs: calendarIDs, start: now, end: futureEnd)
        var seenIDs = Set<String>()
        let legacy = (pastEvents + futureEvents).filter { event in
            BusyEventMarker.isLegacyBusyEvent(event) && seenIDs.insert(event.id).inserted
        }
        for event in legacy {
            store.delete(event)
        }
        logger.info("Deleted \(legacy.count) legacy bee-busy events")
    }

    // MARK: - Dry run (read-only — returns plan + events without executing)

    func dryRun(calendarIDs: [String]) -> (operations: [ReconciliationOperation], events: [CalendarEvent]) {
        guard !calendarIDs.isEmpty else { return ([], []) }
        let window = lookForwardWindow()
        let allEvents = store.fetchEvents(calendarIDs: calendarIDs, start: window.start, end: window.end)
        let (sources, busy) = partition(allEvents)
        let eligible = sources.filter { EventEligibility.isEligible($0, settings: settings) }
        let ops = reconcile(eligibleSources: eligible, busyEvents: busy,
                            configuredCalendarIDs: calendarIDs, windowEnd: window.end)
        return (ops, allEvents)
    }

    // MARK: - Private

    private func subscribeToChanges() {
        notificationObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.scheduleReconciliation()
        }
    }

    private func scheduleReconciliation() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await self?.runReconciliation()
        }
    }

    private func runReconciliation() async {
        let calendarIDs = settings.selectedCalendarIDs
        guard !calendarIDs.isEmpty else { return }

        logger.info("Reconciliation started")
        let window = lookForwardWindow()
        let allEvents = store.fetchEvents(calendarIDs: calendarIDs, start: window.start, end: window.end)
        let (sources, busy) = partition(allEvents)
        let eligible = sources.filter { EventEligibility.isEligible($0, settings: settings) }
        let operations = reconcile(eligibleSources: eligible, busyEvents: busy,
                                   configuredCalendarIDs: calendarIDs, windowEnd: window.end,
                                   logger: logger)

        logger.info("Plan: \(operations.count) operations")
        for op in operations {
            switch op {
            case .create(let draft):
                do {
                    try store.create(draft)
                } catch {
                    logger.error("Failed to create Busy event: \(error)")
                }
            case .delete(let event):
                store.delete(event)
            }
        }

        state.lastSyncDate = Date()
        state.activeCalendarNames = calendarIDs.compactMap { id in
            store.fetchCalendars().first(where: { $0.calendarIdentifier == id })?.title
        }
        logger.info("Reconciliation complete")
    }

    private func partition(_ events: [CalendarEvent]) -> (sources: [CalendarEvent], busy: [CalendarEvent]) {
        var sources: [CalendarEvent] = []
        var busy: [CalendarEvent] = []
        for event in events {
            if BusyEventMarker.isBusyEvent(event) {
                busy.append(event)
            } else {
                sources.append(event)
            }
        }
        return (sources, busy)
    }

    private func lookForwardWindow() -> (start: Date, end: Date) {
        let start = Calendar.current.startOfDay(for: Date())
        let localEnd = Calendar.current.date(byAdding: .day, value: settings.lookForwardDays, to: start)!
        // EKKit normalises EKRecurrenceEnd(end:) to midnight UTC. Round localEnd up to the next
        // UTC midnight so the stored value roundtrips exactly and capStale never fires spuriously.
        let secondsPerDay: TimeInterval = 86400
        let end = Date(timeIntervalSince1970: ceil(localEnd.timeIntervalSince1970 / secondsPerDay) * secondsPerDay)
        return (start, end)
    }
}
