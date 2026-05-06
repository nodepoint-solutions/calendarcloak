import Foundation

struct CalendarEvent: Equatable, Identifiable {
    let id: String            // EKEvent.calendarItemIdentifier (shared across all occurrences of a series)
    let calendarID: String    // EKCalendar.calendarIdentifier
    let calendarName: String  // EKCalendar.title
    let title: String         // EKEvent.title — used ONLY in dry run display, never written to Busy events
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let notes: String?
    let isAccepted: Bool      // pre-computed: no attendees, or currentUser attendee has status .accepted
    let isRecurring: Bool     // non-detached event with recurrence rules
    let isDetached: Bool      // individually modified occurrence of a series
    let seriesEndDate: Date?  // recurrence end date; nil if indefinite or not recurring
}

// Backward-compatible convenience initialiser used by tests and non-recurring call sites.
extension CalendarEvent {
    init(id: String, calendarID: String, calendarName: String, title: String,
         startDate: Date, endDate: Date, isAllDay: Bool, notes: String?, isAccepted: Bool) {
        self.init(id: id, calendarID: calendarID, calendarName: calendarName, title: title,
                  startDate: startDate, endDate: endDate, isAllDay: isAllDay, notes: notes,
                  isAccepted: isAccepted, isRecurring: false, isDetached: false, seriesEndDate: nil)
    }
}
