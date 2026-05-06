import Foundation

struct BusyEventDraft: Equatable {
    let calendarID: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let sourceID: String          // used to construct the notes marker
    let recurrenceCapDate: Date?  // non-nil = create as recurring series capped to this date

    var title: String { "Busy" }
    var notes: String { BusyEventMarker.notes(for: sourceID) }
}

// Backward-compatible convenience initialiser for individual (non-recurring) events.
extension BusyEventDraft {
    init(calendarID: String, startDate: Date, endDate: Date, isAllDay: Bool, sourceID: String) {
        self.init(calendarID: calendarID, startDate: startDate, endDate: endDate,
                  isAllDay: isAllDay, sourceID: sourceID, recurrenceCapDate: nil)
    }
}
