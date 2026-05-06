import EventKit
import Foundation
@testable import CalendarCloak

final class MockCalendarStore: CalendarStoreProtocol {
    var stubbedCalendars: [EKCalendar] = []
    // Separate from stubbedCalendars because EKCalendar requires an EKEventStore to instantiate.
    // Keep both in sync when a test exercises both fetchCalendars() and fetchAllCalendarIDs().
    var stubbedCalendarIDs: [String] = []
    var stubbedEvents: [CalendarEvent] = []
    var createdDrafts: [BusyEventDraft] = []
    var deletedEvents: [CalendarEvent] = []
    var fetchEventsCallCount = 0
    var requestAccessError: Error? = nil

    func requestAccess() async throws {
        if let error = requestAccessError { throw error }
    }

    func fetchCalendars() -> [EKCalendar] {
        stubbedCalendars
    }

    func fetchAllCalendarIDs() -> [String] {
        stubbedCalendarIDs
    }

    func fetchEvents(calendarIDs: [String], start: Date, end: Date) -> [CalendarEvent] {
        fetchEventsCallCount += 1
        return stubbedEvents.filter { calendarIDs.contains($0.calendarID) }
    }

    func create(_ draft: BusyEventDraft) throws {
        createdDrafts.append(draft)
    }

    func delete(_ event: CalendarEvent) {
        deletedEvents.append(event)
    }
}
