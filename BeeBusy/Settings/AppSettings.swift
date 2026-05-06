import Foundation

final class AppSettings {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var selectedCalendarIDs: [String] {
        get { defaults.stringArray(forKey: "selectedCalendarIDs") ?? [] }
        set { defaults.set(newValue, forKey: "selectedCalendarIDs") }
    }

    var lookForwardDays: Int {
        get {
            let v = defaults.integer(forKey: "lookForwardDays")
            return v == 0 ? 30 : v
        }
        set { defaults.set(newValue, forKey: "lookForwardDays") }
    }

    var launchAtLogin: Bool {
        get { defaults.bool(forKey: "launchAtLogin") }
        set { defaults.set(newValue, forKey: "launchAtLogin") }
    }

    var hasCompletedSetup: Bool {
        get { defaults.bool(forKey: "hasCompletedSetup") }
        set { defaults.set(newValue, forKey: "hasCompletedSetup") }
    }
}
