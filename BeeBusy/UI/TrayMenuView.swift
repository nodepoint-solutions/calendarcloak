import SwiftUI

struct TrayMenuView: View {
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow
    let state: AppState
    let settings: AppSettings
    let eventKitStore: EventKitStore
    let engine: SyncEngine
    let logger: Logger

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            statusSection
            Divider()
            calendarSection
            Divider()
            Button("Settings...") {
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            }
            Divider()
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
        .task { await bootstrap() }
    }

    @MainActor
    private func bootstrap() async {
        do {
            try await eventKitStore.requestAccess()
            state.isAccessDenied = false
            if settings.hasCompletedSetup {
                engine.start()
            } else {
                openWindow(id: "setup")
                NSApp.activate(ignoringOtherApps: true)
            }
        } catch {
            state.isAccessDenied = true
            logger.error("EventKit access denied: \(error)")
            showAccessDeniedAlert()
        }
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

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(statusLabel)
                    .font(.callout)
            }
            Text(lastSyncLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var calendarSection: some View {
        Group {
            if !state.activeCalendarNames.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Text("SYNCED CALENDARS")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.top, 6)
                    ForEach(state.activeCalendarNames, id: \.self) { name in
                        Label(name, systemImage: "calendar")
                            .font(.callout)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 3)
                    }
                }
                .padding(.bottom, 6)
                Divider()
            }
        }
    }

    private var statusColor: Color {
        if state.isAccessDenied { return .red }
        if state.errorMessage != nil { return .orange }
        return .green
    }

    private var statusLabel: String {
        if state.isAccessDenied { return "Calendar access denied" }
        return "Active"
    }

    private var lastSyncLabel: String {
        guard let date = state.lastSyncDate else { return "Last sync: Never" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "Last sync: \(formatter.localizedString(for: date, relativeTo: Date()))"
    }
}
