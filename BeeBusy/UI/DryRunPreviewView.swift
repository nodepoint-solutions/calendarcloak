import SwiftUI

struct DryRunPreviewView: View {
    let operations: [ReconciliationOperation]
    let allEvents: [CalendarEvent]
    let onActivate: () -> Void
    let onBack: () -> Void

    private let maxPerGroup = 10

    private var createsBySourceCalendar: [(calendarName: String, calendarID: String, drafts: [BusyEventDraft])] {
        var grouped: [String: (name: String, drafts: [BusyEventDraft])] = [:]
        for case .create(let draft) in operations {
            guard let source = allEvents.first(where: { $0.id == draft.sourceID }) else { continue }
            let key = source.calendarID
            if grouped[key] == nil {
                grouped[key] = (name: source.calendarName, drafts: [])
            }
            grouped[key]!.drafts.append(draft)
        }
        return grouped.map { (calendarID: $0.key, name: $0.value.name, drafts: $0.value.drafts) }
            .sorted { $0.name < $1.name }
            .map { (calendarName: $0.name, calendarID: $0.calendarID, drafts: $0.drafts) }
    }

    private var totalCreates: Int {
        operations.filter { if case .create(_) = $0 { return true }; return false }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Preview")
                    .font(.title2).bold()
                Text("\(totalCreates) Busy event\(totalCreates == 1 ? "" : "s") would be created. Nothing has been written yet.")
                    .foregroundStyle(.secondary)
            }

            if createsBySourceCalendar.isEmpty {
                Text("No eligible events found in the look-forward window.")
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(createsBySourceCalendar, id: \.calendarID) { group in
                            calendarGroup(group)
                        }
                    }
                }
            }

            noticeBox

            HStack(spacing: 8) {
                Button("Activate", action: onActivate)
                    .buttonStyle(.borderedProminent)
                Button("Go Back", action: onBack)
                    .buttonStyle(.bordered)
            }
        }
        .padding()
        .frame(minWidth: 380, maxWidth: 440)
    }

    private func calendarGroup(_ group: (calendarName: String, calendarID: String, drafts: [BusyEventDraft])) -> some View {
        let shown = Array(group.drafts.prefix(maxPerGroup))
        let overflow = group.drafts.count - shown.count
        let targetNames = Set(shown.compactMap { draft in
            allEvents.first(where: { $0.calendarID == draft.calendarID })?.calendarName
        }).sorted().joined(separator: ", ")

        return VStack(alignment: .leading, spacing: 4) {
            Text("FROM \(group.calendarName.uppercased()) → \(targetNames)")
                .font(.caption).bold()
                .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                ForEach(Array(shown.enumerated()), id: \.offset) { index, draft in
                    HStack {
                        // Title shown here is for the user's own preview only — never written to Busy events
                        Text(allEvents.first(where: { $0.id == draft.sourceID })?.title ?? "Event")
                        Spacer()
                        Text(formatRange(start: draft.startDate, end: draft.endDate, isAllDay: draft.isAllDay))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    if index < shown.count - 1 { Divider() }
                }
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            if overflow > 0 {
                Text("+ \(overflow) more not shown")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
            }
        }
    }

    private var noticeBox: some View {
        Text("This preview is shown once. After activating, Bee Busy runs silently in the background — no further prompts.")
            .font(.callout)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.yellow.opacity(0.15))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.yellow.opacity(0.5)))
            .clipShape(RoundedRectangle(cornerRadius: 8))
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
