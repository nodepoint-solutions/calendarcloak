import SwiftUI
import EventKit

struct SetupWizardView: View {
    let store: CalendarStoreProtocol
    let settings: AppSettings
    let engine: SyncEngine
    let onComplete: () -> Void

    @State private var step: Step = .selectCalendars
    @State private var selectedIDs: Set<String> = []
    @State private var allCalendars: [EKCalendar] = []
    @State private var dryRunOperations: [ReconciliationOperation] = []
    @State private var dryRunEvents: [CalendarEvent] = []

    enum Step { case selectCalendars, preview }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            switch step {
            case .selectCalendars: calendarSelectionBody
            case .preview: previewBody
            }
        }
        .frame(width: 520)
        .onAppear { allCalendars = store.fetchCalendars() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 14) {
            Text("🐝")
                .font(.system(size: 40))
            VStack(alignment: .leading, spacing: 2) {
                Text("Bee Busy")
                    .font(.title2).bold()
                Text(step == .selectCalendars
                     ? "Choose which calendars to keep in sync"
                     : "Review what will be created")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            stepIndicator
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var stepIndicator: some View {
        HStack(spacing: 6) {
            ForEach([Step.selectCalendars, .preview], id: \.self) { s in
                Circle()
                    .fill(s == step ? Color.accentColor : Color(nsColor: .separatorColor))
                    .frame(width: 8, height: 8)
            }
        }
    }

    // MARK: - Step 1: Calendar selection

    private var calendarSelectionBody: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if allCalendars.isEmpty {
                        Text("No calendars found.")
                            .foregroundStyle(.secondary)
                            .padding()
                    } else {
                        ForEach(calendarsBySource, id: \.sourceTitle) { group in
                            calendarGroupSection(group)
                        }
                    }
                }
                .padding(24)
            }

            Divider()
            selectionFooter
        }
    }

    private func calendarGroupSection(_ group: (sourceTitle: String, calendars: [EKCalendar])) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(group.sourceTitle)
                .font(.headline)
                .foregroundStyle(.primary)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(group.calendars.enumerated()), id: \.element.calendarIdentifier) { index, cal in
                    Toggle(isOn: Binding(
                        get: { selectedIDs.contains(cal.calendarIdentifier) },
                        set: { on in
                            if on { selectedIDs.insert(cal.calendarIdentifier) }
                            else { selectedIDs.remove(cal.calendarIdentifier) }
                        }
                    )) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Color(cgColor: cal.cgColor))
                                .frame(width: 10, height: 10)
                            Text(cal.title)
                                .font(.body)
                        }
                    }
                    .toggleStyle(.checkbox)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    if index < group.calendars.count - 1 {
                        Divider().padding(.leading, 14)
                    }
                }
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
            )
        }
    }

    private var selectionFooter: some View {
        HStack {
            Group {
                if selectedIDs.isEmpty {
                    Label("Select at least 2 calendars", systemImage: "info.circle")
                } else if selectedIDs.count == 1 {
                    Label("Select one more calendar", systemImage: "info.circle")
                } else {
                    Label("\(selectedIDs.count) calendars selected", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            Spacer()

            Button("Preview") {
                let result = engine.dryRun(calendarIDs: Array(selectedIDs))
                dryRunOperations = result.operations
                dryRunEvents = result.events
                step = .preview
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(selectedIDs.count < 2)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Step 2: Preview

    private var previewBody: some View {
        VStack(spacing: 0) {
            previewContent
            Divider()
            previewFooter
        }
    }

    private var previewContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                let createGroups = createsBySourceCalendar

                if createGroups.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "calendar.badge.checkmark")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text("No events found in the look-forward window.")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                } else {
                    Text("\(totalCreates) Busy event\(totalCreates == 1 ? "" : "s") will be created across your calendars.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    ForEach(createGroups, id: \.calendarID) { group in
                        previewGroupSection(group)
                    }
                }
            }
            .padding(24)
        }
    }

    private func previewGroupSection(_ group: (calendarName: String, calendarID: String, drafts: [BusyEventDraft])) -> some View {
        let shown = Array(group.drafts.prefix(10))
        let overflow = group.drafts.count - shown.count
        let targetNames = Set(shown.compactMap { draft in
            dryRunEvents.first(where: { $0.calendarID == draft.calendarID })?.calendarName
        }).sorted().joined(separator: ", ")

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text(group.calendarName)
                    .font(.headline)
                Image(systemName: "arrow.right")
                    .font(.caption).bold()
                    .foregroundStyle(.secondary)
                Text(targetNames)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(shown.enumerated()), id: \.offset) { index, draft in
                    HStack {
                        Text(dryRunEvents.first(where: { $0.id == draft.sourceID })?.title ?? "Event")
                            .font(.body)
                        Spacer()
                        Text(formatRange(start: draft.startDate, end: draft.endDate, isAllDay: draft.isAllDay))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    if index < shown.count - 1 {
                        Divider().padding(.leading, 14)
                    }
                }
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(nsColor: .separatorColor), lineWidth: 0.5))

            if overflow > 0 {
                Text("+ \(overflow) more not shown")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
            }
        }
    }

    private var previewFooter: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.shield.fill")
                    .foregroundStyle(.green)
                Text("This preview is shown once. After activating, Bee Busy runs silently — no further prompts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.green.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            HStack {
                Button("← Back") { step = .selectCalendars }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                Spacer()
                Button("Activate") {
                    settings.selectedCalendarIDs = Array(selectedIDs)
                    settings.hasCompletedSetup = true
                    engine.start()
                    onComplete()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Helpers

    private var calendarsBySource: [(sourceTitle: String, calendars: [EKCalendar])] {
        let grouped = Dictionary(grouping: allCalendars) { $0.source?.title ?? "Other" }
        return grouped.map { (sourceTitle: $0.key, calendars: $0.value.sorted { $0.title < $1.title }) }
            .sorted { $0.sourceTitle < $1.sourceTitle }
    }

    private var createsBySourceCalendar: [(calendarName: String, calendarID: String, drafts: [BusyEventDraft])] {
        var grouped: [String: (name: String, drafts: [BusyEventDraft])] = [:]
        for case .create(let draft) in dryRunOperations {
            guard let source = dryRunEvents.first(where: { $0.id == draft.sourceID }) else { continue }
            let key = source.calendarID
            if grouped[key] == nil { grouped[key] = (name: source.calendarName, drafts: []) }
            grouped[key]!.drafts.append(draft)
        }
        return grouped.map { (calendarID: $0.key, name: $0.value.name, drafts: $0.value.drafts) }
            .sorted { $0.name < $1.name }
            .map { (calendarName: $0.name, calendarID: $0.calendarID, drafts: $0.drafts) }
    }

    private var totalCreates: Int {
        dryRunOperations.filter { if case .create = $0 { return true }; return false }.count
    }

    private func formatRange(start: Date, end: Date, isAllDay: Bool) -> String {
        if isAllDay { return "All day" }
        let fmt = DateFormatter()
        fmt.dateFormat = "EEE HH:mm"
        let endFmt = DateFormatter()
        endFmt.dateFormat = "HH:mm"
        return "\(fmt.string(from: start))–\(endFmt.string(from: end))"
    }
}

extension SetupWizardView.Step: Hashable {}
