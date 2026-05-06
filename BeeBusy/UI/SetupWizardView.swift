import SwiftUI
import EventKit

struct SetupWizardView: View {
    let store: CalendarStoreProtocol
    let settings: AppSettings
    let engine: SyncEngine
    let onComplete: () -> Void  // called on Activate; caller is responsible for closing the window

    @State private var step: Step = .selectCalendars
    @State private var selectedIDs: Set<String> = []
    @State private var allCalendars: [EKCalendar] = []
    @State private var dryRunOperations: [ReconciliationOperation] = []
    @State private var dryRunEvents: [CalendarEvent] = []

    enum Step { case selectCalendars, preview }

    var body: some View {
        Group {
            switch step {
            case .selectCalendars:
                calendarSelectionView
            case .preview:
                DryRunPreviewView(
                    operations: dryRunOperations,
                    allEvents: dryRunEvents,
                    onActivate: {
                        settings.selectedCalendarIDs = Array(selectedIDs)
                        settings.hasCompletedSetup = true
                        engine.start()
                        onComplete()
                    },
                    onBack: { step = .selectCalendars }
                )
            }
        }
        .onAppear { allCalendars = store.fetchCalendars() }
    }

    private var calendarSelectionView: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Set Up Bee Busy")
                    .font(.title2).bold()
                Text("Select which calendars to keep in sync. Nothing is saved until you accept the preview.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if allCalendars.isEmpty {
                Text("No calendars found.")
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(calendarsBySource, id: \.sourceTitle) { group in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(group.sourceTitle.uppercased())
                                    .font(.caption2).bold()
                                    .foregroundStyle(.secondary)
                                VStack(spacing: 0) {
                                    ForEach(group.calendars, id: \.calendarIdentifier) { cal in
                                        Toggle(isOn: Binding(
                                            get: { selectedIDs.contains(cal.calendarIdentifier) },
                                            set: { on in
                                                if on { selectedIDs.insert(cal.calendarIdentifier) }
                                                else { selectedIDs.remove(cal.calendarIdentifier) }
                                            }
                                        )) {
                                            Label {
                                                Text(cal.title)
                                            } icon: {
                                                Circle()
                                                    .fill(Color(cgColor: cal.cgColor))
                                                    .frame(width: 10, height: 10)
                                            }
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        if cal.calendarIdentifier != group.calendars.last?.calendarIdentifier {
                                            Divider().padding(.leading, 12)
                                        }
                                    }
                                }
                                .background(Color(nsColor: .controlBackgroundColor))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                }
            }

            HStack {
                if selectedIDs.count < 2 {
                    Text(selectedIDs.isEmpty ? "Select at least 2 calendars to continue." : "Select one more calendar to continue.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Preview →") {
                    let result = engine.dryRun(calendarIDs: Array(selectedIDs))
                    dryRunOperations = result.operations
                    dryRunEvents = result.events
                    step = .preview
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedIDs.count < 2)
            }
        }
        .padding()
        .frame(minWidth: 380, maxWidth: 440, minHeight: 300)
    }

    private var calendarsBySource: [(sourceTitle: String, calendars: [EKCalendar])] {
        let grouped = Dictionary(grouping: allCalendars) { $0.source?.title ?? "Other" }
        return grouped.map { (sourceTitle: $0.key, calendars: $0.value.sorted { $0.title < $1.title }) }
            .sorted { $0.sourceTitle < $1.sourceTitle }
    }
}
