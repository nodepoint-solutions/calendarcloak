import Foundation

struct CalendarEvent: Equatable, Identifiable {
    let id: String            // EKEvent.calendarItemIdentifier
    let calendarID: String    // EKCalendar.calendarIdentifier
    let calendarName: String  // EKCalendar.title
    let title: String         // EKEvent.title — used ONLY in dry run display, never written to Busy events
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let notes: String?
    let isAccepted: Bool      // pre-computed: no attendees, or currentUser attendee has status .accepted
}
