import Foundation

enum EventEligibility {
    /// Returns true if the event should be mirrored as a Busy block in other calendars.
    /// Rejects events the user has not explicitly accepted, and rejects our own Busy events
    /// as a belt-and-suspenders guard against recursive syncing.
    static func isEligible(_ event: CalendarEvent) -> Bool {
        guard !BusyEventMarker.isBusyEvent(event) else { return false }
        return event.isAccepted
    }
}
