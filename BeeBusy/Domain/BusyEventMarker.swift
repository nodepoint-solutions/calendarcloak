import Foundation

enum BusyEventMarker {
    private static let prefix = "bee-busy:source="

    static func notes(for sourceID: String) -> String {
        "\(prefix)\(sourceID)"
    }

    static func sourceID(from notes: String?) -> String? {
        guard let notes, notes.hasPrefix(prefix) else { return nil }
        let extracted = String(notes.dropFirst(prefix.count))
        return extracted.isEmpty ? nil : extracted
    }

    /// Returns false if the event has no marker, or if notes were externally cleared after creation.
    static func isBusyEvent(_ event: CalendarEvent) -> Bool {
        sourceID(from: event.notes) != nil
    }
}
