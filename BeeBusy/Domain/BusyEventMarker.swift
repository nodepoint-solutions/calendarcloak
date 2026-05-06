import Foundation

enum BusyEventMarker {
    static let prefix = "bee-busy:source="

    static func notes(for sourceID: String) -> String {
        "\(prefix)\(sourceID)"
    }

    static func sourceID(from notes: String?) -> String? {
        guard let notes, notes.hasPrefix(prefix) else { return nil }
        return String(notes.dropFirst(prefix.count))
    }

    static func isBusyEvent(_ event: CalendarEvent) -> Bool {
        sourceID(from: event.notes) != nil
    }
}
