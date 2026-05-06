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

    // MARK: - Dry run (read-only — returns plan + events without executing)

    func dryRun(calendarIDs: [String]) -> (operations: [ReconciliationOperation], events: [CalendarEvent]) {
        guard !calendarIDs.isEmpty else { return ([], []) }
        let window = lookForwardWindow()
        let allEvents = store.fetchEvents(calendarIDs: calendarIDs, start: window.start, end: window.end)
        let (sources, busy) = partition(allEvents)
        let eligible = sources.filter { EventEligibility.isEligible($0) }
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
        let eligible = sources.filter { EventEligibility.isEligible($0) }
        let operations = reconcile(eligibleSources: eligible, busyEvents: busy,
                                   configuredCalendarIDs: calendarIDs, windowEnd: window.end)

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
        let end = Calendar.current.date(byAdding: .day, value: settings.lookForwardDays, to: start)!
        return (start, end)
    }
}
