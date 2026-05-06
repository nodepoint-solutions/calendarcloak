import SwiftUI
import EventKit

@main
struct BeeBusyApp: App {
    private let logger: Logger = {
        let logsURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("Logs/BeeBusy/bee-busy.log")
        return Logger(fileURL: logsURL)
    }()

    private let settings = AppSettings()
    private let state = AppState()
    private let eventKitStore: EventKitStore
    private let engine: SyncEngine

    @State private var showDryRun = false
    @State private var dryRunOperations: [ReconciliationOperation] = []
    @State private var dryRunAllEvents: [CalendarEvent] = []

    init() {
        let ekStore = EventKitStore(logger: logger)
        eventKitStore = ekStore
        engine = SyncEngine(store: ekStore, settings: settings, state: state, logger: logger)
    }

    var body: some Scene {
        MenuBarExtra("Bee Busy", systemImage: "calendar.badge.clock") {
            TrayMenuView(state: state)
                .task { await requestAccessAndStart() }
                .sheet(isPresented: $showDryRun) {
                    DryRunPreviewView(
                        operations: dryRunOperations,
                        allEvents: dryRunAllEvents,
                        onActivate: {
                            showDryRun = false
                            settings.hasCompletedSetup = true
                            engine.start()
                        },
                        onBack: {
                            showDryRun = false
                        }
                    )
                }
        }

        Settings {
            SettingsView(
                settings: settings,
                store: eventKitStore,
                logger: logger,
                engine: engine
            )
        }
    }

    // MARK: - Private

    @MainActor
    private func requestAccessAndStart() async {
        do {
            try await eventKitStore.requestAccess()
            state.isAccessDenied = false
            if settings.hasCompletedSetup {
                engine.start()
            } else {
                await waitForCalendarSelectionThenDryRun()
            }
        } catch {
            state.isAccessDenied = true
            logger.error("EventKit access denied: \(error)")
            showAccessDeniedAlert()
        }
    }

    @MainActor
    private func waitForCalendarSelectionThenDryRun() async {
        while settings.selectedCalendarIDs.isEmpty {
            try? await Task.sleep(for: .seconds(1))
        }
        let calIDs = settings.selectedCalendarIDs
        let window = (
            start: Calendar.current.startOfDay(for: Date()),
            end: Calendar.current.date(byAdding: .day, value: settings.lookForwardDays, to: Date())!
        )
        dryRunAllEvents = eventKitStore.fetchEvents(calendarIDs: calIDs, start: window.start, end: window.end)
        dryRunOperations = engine.dryRun()
        showDryRun = true
    }

    private func showAccessDeniedAlert() {
        let alert = NSAlert()
        alert.messageText = "Calendar Access Required"
        alert.informativeText = "Bee Busy needs full calendar access to sync Busy events. Please grant access in System Settings → Privacy & Security → Calendars."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Quit")
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
        } else {
            NSApplication.shared.terminate(nil)
        }
    }
}
