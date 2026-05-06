import Foundation

enum BusyEventMarker {
    private static let prefix = "calendarcloak:source="
    private static let legacyPrefix = "bee-busy:source="

    static func notes(for sourceID: String) -> String {
        "\(prefix)\(sourceID)"
    }

    static func sourceID(from notes: String?) -> String? {
        guard let notes, notes.hasPrefix(prefix) else { return nil }
        let extracted = String(notes.dropFirst(prefix.count))
        return extracted.isEmpty ? nil : extracted
    }

    static func isBusyEvent(_ event: CalendarEvent) -> Bool {
        sourceID(from: event.notes) != nil
    }

    static func isLegacyBusyEvent(_ event: CalendarEvent) -> Bool {
        event.notes?.hasPrefix(legacyPrefix) == true
    }
}
