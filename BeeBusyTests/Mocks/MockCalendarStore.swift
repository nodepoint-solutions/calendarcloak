import EventKit
import Foundation
@testable import BeeBusy

final class MockCalendarStore: CalendarStoreProtocol {
    var stubbedCalendars: [EKCalendar] = []
    var stubbedEvents: [CalendarEvent] = []
    var createdDrafts: [BusyEventDraft] = []
    var deletedEvents: [CalendarEvent] = []
    var requestAccessError: Error? = nil

    func requestAccess() async throws {
        if let error = requestAccessError { throw error }
    }

    func fetchCalendars() -> [EKCalendar] {
        stubbedCalendars
    }

    func fetchEvents(calendarIDs: [String], start: Date, end: Date) -> [CalendarEvent] {
        stubbedEvents.filter { calendarIDs.contains($0.calendarID) }
    }

    func create(_ draft: BusyEventDraft) throws {
        createdDrafts.append(draft)
    }

    func delete(_ event: CalendarEvent) {
        deletedEvents.append(event)
    }
}
