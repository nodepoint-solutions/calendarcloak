import Foundation

enum EventEligibility {
    static func isEligible(_ event: CalendarEvent, settings: AppSettings) -> Bool {
        guard !BusyEventMarker.isBusyEvent(event) else { return false }
        guard event.isAccepted else { return false }

        if event.isAllDay {
            return settings.includeAllDayEvents
        }

        if settings.workHoursEnabled {
            let hour = Calendar.current.component(.hour, from: event.startDate)
            guard hour >= settings.workHoursStart && hour < settings.workHoursEnd else { return false }
        }

        return true
    }
}
