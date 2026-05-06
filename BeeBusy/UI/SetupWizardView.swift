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

    enum Step: Hashable { case selectCalendars, preview }

    var body: some View {
        VStack(spacing: 0) {
            wizardHeader
            Divider()
            switch step {
            case .selectCalendars: calendarSelectionStep
            case .preview: previewStep
            }
        }
        .frame(width: 820)
        .onAppear { allCalendars = store.fetchCalendars() }
    }

    // MARK: - Header

    private var wizardHeader: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.yellow.opacity(0.15))
                    .frame(width: 48, height: 48)
                Text("🐝").font(.system(size: 26))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Bee Busy").font(.title2).bold()
                Text(step == .selectCalendars
                     ? "Select calendars to keep in sync"
                     : "Preview — Busy blocks that will be created")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 10) {
                stepLabel(number: 1, title: "Calendars", current: step == .selectCalendars)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                stepLabel(number: 2, title: "Preview", current: step == .preview)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }

    private func stepLabel(number: Int, title: String, current: Bool) -> some View {
        HStack(spacing: 5) {
            Text("\(number)")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(current ? .white : Color(nsColor: .tertiaryLabelColor))
                .frame(width: 17, height: 17)
                .background(current ? Color.accentColor : Color(nsColor: .separatorColor))
                .clipShape(Circle())
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(current ? .primary : Color(nsColor: .tertiaryLabelColor))
        }
    }

    // MARK: - Step 1: Calendar Selection

    private var calendarSelectionStep: some View {
        VStack(spacing: 0) {
            syncConceptBanner
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if allCalendars.isEmpty {
                        Text("No calendars found.").foregroundStyle(.secondary).padding()
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

    private var syncConceptBanner: some View {
        HStack(spacing: 14) {
            Image(systemName: "lock.shield.fill")
                .font(.title3)
                .foregroundStyle(Color.accentColor.opacity(0.85))
            VStack(alignment: .leading, spacing: 3) {
                Text("Only \u{201C}Busy\u{201D} is shared \u{2014} your event details stay private")
                    .font(.subheadline).bold()
                Text("Events from each calendar appear as anonymous time blocks in all your other selected calendars.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color.accentColor.opacity(0.05))
    }

    private func calendarGroupSection(_ group: (sourceTitle: String, calendars: [EKCalendar])) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(group.sourceTitle).font(.subheadline).bold()
            VStack(spacing: 0) {
                ForEach(Array(group.calendars.enumerated()), id: \.element.calendarIdentifier) { idx, cal in
                    Toggle(isOn: Binding(
                        get: { selectedIDs.contains(cal.calendarIdentifier) },
                        set: { on in
                            if on { selectedIDs.insert(cal.calendarIdentifier) }
                            else { selectedIDs.remove(cal.calendarIdentifier) }
                        }
                    )) {
                        HStack(spacing: 9) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color(cgColor: cal.cgColor))
                                .frame(width: 12, height: 12)
                            Text(cal.title)
                        }
                    }
                    .toggleStyle(.checkbox)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    if idx < group.calendars.count - 1 { Divider().padding(.leading, 14) }
                }
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(nsColor: .separatorColor), lineWidth: 0.5))
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
                    Label("\(selectedIDs.count) calendars will sync with each other as \u{201C}Busy\u{201D}", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            Spacer()
            let allSelected = selectedIDs.count == allCalendars.count
            Button(allSelected ? "Select None" : "Select All") {
                if allSelected {
                    selectedIDs.removeAll()
                } else {
                    selectedIDs = Set(allCalendars.map { $0.calendarIdentifier })
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            Button("See Preview") {
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

    private var previewStep: some View {
        VStack(spacing: 0) {
            previewInfoBar
            Divider()
            if sourceOccurrences.isEmpty {
                emptyPreview
            } else {
                WizardWeekCalendar(sourceOccurrences: sourceOccurrences, weekDays: previewWeekDays)
                    .padding(16)
            }
            Divider()
            previewFooter
        }
    }

    private var previewInfoBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.fill").font(.caption).foregroundStyle(.secondary)
            Text("Only the time is blocked \u{2014} no titles, locations, or details are ever shared")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            let uniqueCount = Set(sourceOccurrences.map { $0.id }).count
            if uniqueCount > 0 {
                Text("\(uniqueCount) event\(uniqueCount == 1 ? "" : "s") \u{2192} Busy")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(nsColor: .separatorColor).opacity(0.4))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var emptyPreview: some View {
        VStack(spacing: 10) {
            Image(systemName: "calendar.badge.checkmark").font(.system(size: 36)).foregroundStyle(.secondary)
            Text("No upcoming events in the sync window").font(.subheadline).foregroundStyle(.secondary)
            Text("Bee Busy will sync events as they appear.").font(.caption).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 220)
    }

    private var previewFooter: some View {
        HStack {
            Button("\u{2190} Back") { step = .selectCalendars }
                .buttonStyle(.bordered)
                .controlSize(.large)
            Spacer()
            Button("Activate Bee Busy") {
                settings.selectedCalendarIDs = Array(selectedIDs)
                settings.hasCompletedSetup = true
                engine.start()
                onComplete()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
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

    private var allBusyDrafts: [BusyEventDraft] {
        dryRunOperations.compactMap { if case .create(let d) = $0 { return d }; return nil }
    }

    // All source event occurrences (individual + every recurring occurrence) that will become Busy.
    // EventKit returns each recurring occurrence as a distinct CalendarEvent in dryRunEvents,
    // all sharing the same .id (calendarItemIdentifier = series ID). We match against draft sourceIDs.
    private var sourceOccurrences: [CalendarEvent] {
        let busySourceIDs = Set(allBusyDrafts.map { $0.sourceID })
        return dryRunEvents.filter { busySourceIDs.contains($0.id) && !BusyEventMarker.isBusyEvent($0) }
    }

    // Show 7-day windows starting from today, advancing 7 days at a time until one has events.
    // Starts from today rather than Monday because we only sync future events.
    private var previewWeekDays: [Date] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        for offset in 0..<8 {
            let start = cal.date(byAdding: .day, value: offset * 7, to: today)!
            let days = (0..<7).map { cal.date(byAdding: .day, value: $0, to: start)! }
            if sourceOccurrences.contains(where: { ev in days.contains { cal.isDate(ev.startDate, inSameDayAs: $0) } }) {
                return days
            }
        }
        return (0..<7).map { cal.date(byAdding: .day, value: $0, to: today)! }
    }
}

// MARK: - Week Calendar

private struct WizardWeekCalendar: View {
    let sourceOccurrences: [CalendarEvent]
    let weekDays: [Date]  // 7 days Mon–Sun

    // Reduce density: tighter hours, smaller row height
    private let hourHeight: CGFloat = 34
    private let startHour: Int = 8
    private let endHour: Int = 19   // 8 AM – 7 PM = 11 hours visible
    private let timeWidth: CGFloat = 40  // MUST match across all rows for alignment

    private var totalHeight: CGFloat { CGFloat(endHour - startHour) * hourHeight }

    var body: some View {
        VStack(spacing: 0) {
            dayHeaderRow
            hairline
            allDayRow
            hairline
            timeGridRow  // no ScrollView — full height is visible
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(nsColor: .separatorColor), lineWidth: 0.5))
    }

    // MARK: Rows — each shares the exact same column structure for alignment

    private var dayHeaderRow: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: timeWidth, height: 38)
            vline
            ForEach(Array(weekDays.enumerated()), id: \.offset) { idx, day in
                VStack(spacing: 1) {
                    Text(dayAbbrev(day))
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                    ZStack {
                        if Calendar.current.isDateInToday(day) {
                            Circle().fill(Color.accentColor).frame(width: 20, height: 20)
                        }
                        Text(dayNum(day))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Calendar.current.isDateInToday(day) ? .white : .primary)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 38)
                if idx < weekDays.count - 1 { vline }
            }
        }
    }

    private var allDayRow: some View {
        HStack(spacing: 0) {
            Text("all-day")
                .font(.system(size: 8))
                .foregroundStyle(.quaternary)
                .frame(width: timeWidth, height: 18)
                .multilineTextAlignment(.trailing)
                .padding(.trailing, 4)
            vline
            ForEach(Array(weekDays.enumerated()), id: \.offset) { idx, day in
                let events = occurrencesForDay(day).filter { $0.isAllDay }
                ZStack {
                    if !events.isEmpty {
                        Text("Busy")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 2)
                            .background(Color(nsColor: .systemGray).opacity(0.2))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                            .padding(.horizontal, 2)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 18)
                if idx < weekDays.count - 1 { vline }
            }
        }
        .frame(height: 18)
    }

    private var timeGridRow: some View {
        HStack(alignment: .top, spacing: 0) {
            // Time labels — width MUST equal timeWidth to keep columns aligned
            VStack(spacing: 0) {
                ForEach(startHour..<endHour, id: \.self) { h in
                    Text(hourLabel(h))
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                        .frame(width: timeWidth, height: hourHeight, alignment: .topTrailing)
                        .padding(.trailing, 4)
                        .padding(.top, 2)
                }
            }
            vline
            ForEach(Array(weekDays.enumerated()), id: \.offset) { idx, day in
                dayColumn(for: day)
                if idx < weekDays.count - 1 { vline }
            }
        }
        .frame(height: totalHeight)
    }

    // MARK: Day column

    private func dayColumn(for day: Date) -> some View {
        let events = occurrencesForDay(day).filter { !$0.isAllDay }

        return ZStack(alignment: .topLeading) {
            // Background grid: solid line at each hour, dashed at half-hour
            VStack(spacing: 0) {
                ForEach(startHour..<endHour, id: \.self) { _ in
                    VStack(spacing: 0) {
                        Color(nsColor: .separatorColor).opacity(0.45).frame(height: 0.5)
                        Color.clear.frame(height: hourHeight / 2 - 0.5)
                        Color(nsColor: .separatorColor).opacity(0.18).frame(height: 0.5)
                        Color.clear.frame(height: hourHeight / 2 - 0.5)
                    }
                }
            }
            .frame(maxWidth: .infinity)

            // Busy blocks positioned by time
            ForEach(Array(events.enumerated()), id: \.offset) { _, event in
                let y = yPos(event.startDate)
                let h = max(blockHeight(event.startDate, event.endDate), 14)
                if y < totalHeight {
                    busyBlock(height: h)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 1)
                        .offset(y: y)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: totalHeight)
        .clipped()
    }

    private func busyBlock(height: CGFloat) -> some View {
        HStack(spacing: 2) {
            RoundedRectangle(cornerRadius: 1)
                .fill(Color(nsColor: .systemGray).opacity(0.65))
                .frame(width: 2)
            if height >= 18 {
                Text("Busy")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 1)
        .frame(height: height, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(nsColor: .systemGray).opacity(0.11))
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(Color(nsColor: .systemGray).opacity(0.22), lineWidth: 0.5)
                )
        )
    }

    // MARK: Helpers

    // Shared hairline views — using Color rather than Divider ensures exact 0.5pt sizing
    private var hairline: some View {
        Color(nsColor: .separatorColor).frame(height: 0.5)
    }

    private var vline: some View {
        Color(nsColor: .separatorColor).frame(width: 0.5)
    }

    private func occurrencesForDay(_ day: Date) -> [CalendarEvent] {
        sourceOccurrences.filter { Calendar.current.isDate($0.startDate, inSameDayAs: day) }
    }

    private func yPos(_ date: Date) -> CGFloat {
        let c = Calendar.current
        let h = c.component(.hour, from: date)
        let m = c.component(.minute, from: date)
        return CGFloat(max(0, Double(h - startHour) + Double(m) / 60.0)) * hourHeight
    }

    private func blockHeight(_ start: Date, _ end: Date) -> CGFloat {
        CGFloat(end.timeIntervalSince(start) / 3600) * hourHeight
    }

    private func dayAbbrev(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "EEE"; return f.string(from: d).uppercased()
    }

    private func dayNum(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "d"; return f.string(from: d)
    }

    private func hourLabel(_ h: Int) -> String {
        h == 12 ? "12 PM" : h > 12 ? "\(h-12) PM" : "\(h) AM"
    }
}
