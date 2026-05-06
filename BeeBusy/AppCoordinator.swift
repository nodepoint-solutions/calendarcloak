import SwiftUI

/// Owns app-level lifecycle: EventKit access, first-launch setup window, engine start.
/// Lives outside the SwiftUI view hierarchy so it runs on app launch, not on first tray click.
@MainActor
final class AppCoordinator {
    private var setupWindowController: NSWindowController?

    func bootstrap(
        settings: AppSettings,
        state: AppState,
        eventKitStore: EventKitStore,
        engine: SyncEngine,
        logger: Logger
    ) {
        Task {
            do {
                try await eventKitStore.requestAccess()
                state.isAccessDenied = false
                // Treat fewer than 2 calendars as unconfigured regardless of hasCompletedSetup —
                // covers the case where the user closed the wizard without finishing, or removed
                // all calendars from Settings after initial setup.
                if settings.hasCompletedSetup && settings.selectedCalendarIDs.count >= 2 {
                    engine.start()
                } else {
                    settings.hasCompletedSetup = false  // reset so Activate re-sets it cleanly
                    openSetupWindow(store: eventKitStore, settings: settings, engine: engine)
                }
            } catch {
                state.isAccessDenied = true
                logger.error("EventKit access denied: \(error)")
                showAccessDeniedAlert()
            }
        }
    }

    func openSetupWindow(store: CalendarStoreProtocol, settings: AppSettings, engine: SyncEngine) {
        let view = SetupWizardView(
            store: store,
            settings: settings,
            engine: engine,
            onComplete: { [weak self] in
                self?.setupWindowController?.close()
                self?.setupWindowController = nil
            }
        )
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Set Up Bee Busy"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 520, height: 560))
        window.center()
        window.isReleasedWhenClosed = false
        let controller = NSWindowController(window: window)
        setupWindowController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showAccessDeniedAlert() {
        let alert = NSAlert()
        alert.messageText = "Calendar Access Required"
        alert.informativeText = "Bee Busy needs full calendar access. Please grant access in System Settings → Privacy & Security → Calendars."
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
