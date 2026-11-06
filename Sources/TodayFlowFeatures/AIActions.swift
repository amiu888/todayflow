import Foundation

/// AI entry points exposed by the main Today panel. Hosts inject these so the
/// panel can surface AI actions without importing the Mac composition root.
public struct AIActions: Sendable {
    public var ask: @MainActor @Sendable () -> Void
    public var plan: @MainActor @Sendable () -> Void
    public var configure: @MainActor @Sendable () -> Void
    public var settings: @MainActor @Sendable () -> Void

    public init(
        ask: @escaping @MainActor @Sendable () -> Void,
        plan: @escaping @MainActor @Sendable () -> Void,
        configure: @escaping @MainActor @Sendable () -> Void,
        settings: @escaping @MainActor @Sendable () -> Void
    ) {
        self.ask = ask
        self.plan = plan
        self.configure = configure
        self.settings = settings
    }
}
