import SwiftUI

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

    init() {
        let ekStore = EventKitStore(logger: logger)
        eventKitStore = ekStore
        engine = SyncEngine(store: ekStore, settings: settings, state: state, logger: logger)
    }

    var body: some Scene {
        MenuBarExtra("Bee Busy", systemImage: "calendar.badge.clock") {
            TrayMenuView(
                state: state,
                settings: settings,
                eventKitStore: eventKitStore,
                engine: engine,
                logger: logger
            )
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
