import SwiftUI
import EventKit
import ServiceManagement

struct SettingsView: View {
    @State private var calendars: [EKCalendar] = []
    let settings: AppSettings
    let store: CalendarStoreProtocol
    let logger: Logger
    let engine: SyncEngine

    var body: some View {
        Form {
            Section("Calendars") {
                if calendars.isEmpty {
                    Text("No calendars available")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(calendars, id: \.calendarIdentifier) { calendar in
                        Toggle(isOn: bindingFor(calendar)) {
                            Label {
                                Text(calendar.title)
                            } icon: {
                                Circle()
                                    .fill(Color(cgColor: calendar.cgColor))
                                    .frame(width: 10, height: 10)
                            }
                        }
                    }
                }
            }

            Section("Look-forward window") {
                HStack {
                    Slider(
                        value: Binding(
                            get: { Double(settings.lookForwardDays) },
                            set: { settings.lookForwardDays = Int($0) }
                        ),
                        in: 1...90,
                        step: 1
                    )
                    Text("\(settings.lookForwardDays) days")
                        .monospacedDigit()
                        .frame(width: 60, alignment: .trailing)
                }
            }

            Section("General") {
                Toggle("Launch at login", isOn: Binding(
                    get: { settings.launchAtLogin },
                    set: { newValue in
                        settings.launchAtLogin = newValue
                        applyLaunchAtLogin(newValue)
                    }
                ))

                Button("View Logs") {
                    let logsURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)
                        .first!
                        .appendingPathComponent("Logs/BeeBusy/bee-busy.log")
                    NSWorkspace.shared.open(logsURL)
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 360)
        .padding()
        .onAppear { calendars = store.fetchCalendars() }
    }

    private func bindingFor(_ calendar: EKCalendar) -> Binding<Bool> {
        Binding(
            get: { settings.selectedCalendarIDs.contains(calendar.calendarIdentifier) },
            set: { isOn in
                var ids = settings.selectedCalendarIDs
                if isOn {
                    ids.append(calendar.calendarIdentifier)
                    settings.selectedCalendarIDs = ids
                } else {
                    ids.removeAll { $0 == calendar.calendarIdentifier }
                    settings.selectedCalendarIDs = ids
                    Task { @MainActor in
                        engine.cleanupRemovedCalendar(id: calendar.calendarIdentifier)
                    }
                }
            }
        )
    }

    private func applyLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            logger.error("Launch at login failed: \(error)")
        }
    }
}
