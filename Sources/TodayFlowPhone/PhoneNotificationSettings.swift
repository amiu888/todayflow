#if os(iOS)
import Foundation
import Observation

/// The two notification switches in Settings, kept in UserDefaults.
@MainActor
@Observable
public final class PhoneNotificationSettings {
    private let defaults: UserDefaults
    /// Called after either switch changes, to reschedule.
    @ObservationIgnored var onChange: (@MainActor () -> Void)?

    public var remindersOn: Bool {
        didSet { defaults.set(remindersOn, forKey: "notifications.reminders"); onChange?() }
    }
    public var nudgesOn: Bool {
        didSet { defaults.set(nudgesOn, forKey: "notifications.nudges"); onChange?() }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        remindersOn = defaults.object(forKey: "notifications.reminders") as? Bool ?? true
        nudgesOn = defaults.object(forKey: "notifications.nudges") as? Bool ?? true
    }
}
#endif
