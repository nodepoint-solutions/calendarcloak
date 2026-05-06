import Foundation
import Observation

enum UpdateState: Equatable {
    case idle
    case available(version: String, dmgUrl: URL)
    case downloading(pct: Double)
    case installing
    case restarting
}

@Observable
final class AppState {
    var lastSyncDate: Date?
    var activeCalendarNames: [String] = []
    var isAccessDenied: Bool = false
    var errorMessage: String?
    var updateState: UpdateState = .idle
}
