import SwiftUI

@main
struct CalendarCloakApp: App {
    private let logger: Logger = {
        let logsURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("Logs/CalendarCloak/calendar-cloak.log")
        return Logger(fileURL: logsURL)
    }()

    private let settings = AppSettings()
    private let state = AppState()
    private let eventKitStore: EventKitStore
    private let engine: SyncEngine
    private let coordinator = AppCoordinator()

    init() {
        let ekStore = EventKitStore(logger: logger)
        eventKitStore = ekStore
        engine = SyncEngine(store: ekStore, settings: settings, state: state, logger: logger)

        // Bootstrap immediately on launch — not deferred to first tray click
        let s = settings, st = state, ek = ekStore, e = engine, l = logger
        let c = coordinator
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            c.bootstrap(settings: s, state: st, eventKitStore: ek, engine: e, logger: l)
        }
    }

    var body: some Scene {
        MenuBarExtra("CalendarCloak", systemImage: "calendar.badge.clock") {
            TrayMenuView(state: state, logger: logger)
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
}
