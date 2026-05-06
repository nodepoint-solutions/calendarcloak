import Foundation
import Observation

@Observable
final class AppState {
    var lastSyncDate: Date?
    var activeCalendarNames: [String] = []
    var isAccessDenied: Bool = false
    var errorMessage: String?
}
