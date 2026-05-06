import Foundation

struct BusyEventDraft: Equatable {
    let calendarID: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let sourceID: String  // used to construct the notes marker

    var title: String { "Busy" }
    var notes: String { BusyEventMarker.notes(for: sourceID) }
}
