import SwiftUI

struct TrayMenuView: View {
    @Environment(\.openSettings) private var openSettings
    let state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            statusSection
            Divider()
            Button("Settings...") {
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            }
            Divider()
            Button("Quit") { NSApplication.shared.terminate(nil) }
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
            if !state.activeCalendarNames.isEmpty {
                Text("Watching \(state.activeCalendarNames.count) calendar\(state.activeCalendarNames.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            TimelineView(.everyMinute) { _ in
                Text(lastSyncLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var statusColor: Color {
        if state.isAccessDenied { return .red }
        if state.errorMessage != nil { return .orange }
        return .green
    }

    private var statusLabel: String {
        state.isAccessDenied ? "Calendar access denied" : "Active"
    }

    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()

    private var lastSyncLabel: String {
        guard let date = state.lastSyncDate else { return "Last sync: Never" }
        return "Last sync: \(Self.relativeDateFormatter.localizedString(for: date, relativeTo: Date()))"
    }
}
