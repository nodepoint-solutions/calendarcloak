import Foundation
import Observation

@Observable
final class AppSettings {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var selectedCalendarIDs: [String] {
        get {
            access(keyPath: \.selectedCalendarIDs)
            return defaults.stringArray(forKey: "selectedCalendarIDs") ?? []
        }
        set {
            withMutation(keyPath: \.selectedCalendarIDs) {
                defaults.set(newValue, forKey: "selectedCalendarIDs")
            }
        }
    }

    var lookForwardDays: Int {
        get {
            access(keyPath: \.lookForwardDays)
            let v = defaults.integer(forKey: "lookForwardDays")
            return v == 0 ? 30 : v
        }
        set {
            withMutation(keyPath: \.lookForwardDays) {
                defaults.set(newValue, forKey: "lookForwardDays")
            }
        }
    }

    var launchAtLogin: Bool {
        get {
            access(keyPath: \.launchAtLogin)
            return defaults.bool(forKey: "launchAtLogin")
        }
        set {
            withMutation(keyPath: \.launchAtLogin) {
                defaults.set(newValue, forKey: "launchAtLogin")
            }
        }
    }

    var hasCompletedSetup: Bool {
        get {
            access(keyPath: \.hasCompletedSetup)
            return defaults.bool(forKey: "hasCompletedSetup")
        }
        set {
            withMutation(keyPath: \.hasCompletedSetup) {
                defaults.set(newValue, forKey: "hasCompletedSetup")
            }
        }
    }

    var includeAllDayEvents: Bool {
        get {
            access(keyPath: \.includeAllDayEvents)
            guard defaults.object(forKey: "includeAllDayEvents") != nil else { return true }
            return defaults.bool(forKey: "includeAllDayEvents")
        }
        set {
            withMutation(keyPath: \.includeAllDayEvents) {
                defaults.set(newValue, forKey: "includeAllDayEvents")
            }
        }
    }

    var workHoursEnabled: Bool {
        get {
            access(keyPath: \.workHoursEnabled)
            return defaults.bool(forKey: "workHoursEnabled")
        }
        set {
            withMutation(keyPath: \.workHoursEnabled) {
                defaults.set(newValue, forKey: "workHoursEnabled")
            }
        }
    }

    var workHoursStart: Int {
        get {
            access(keyPath: \.workHoursStart)
            guard defaults.object(forKey: "workHoursStart") != nil else { return 9 }
            return defaults.integer(forKey: "workHoursStart")
        }
        set {
            withMutation(keyPath: \.workHoursStart) {
                defaults.set(newValue, forKey: "workHoursStart")
            }
        }
    }

    var workHoursEnd: Int {
        get {
            access(keyPath: \.workHoursEnd)
            guard defaults.object(forKey: "workHoursEnd") != nil else { return 18 }
            return defaults.integer(forKey: "workHoursEnd")
        }
        set {
            withMutation(keyPath: \.workHoursEnd) {
                defaults.set(newValue, forKey: "workHoursEnd")
            }
        }
    }
}
