import Foundation

enum ReconciliationOperation: Equatable {
    case create(BusyEventDraft)
    case delete(CalendarEvent)
}
