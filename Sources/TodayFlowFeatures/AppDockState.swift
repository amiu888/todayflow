import Foundation

/// The dock-to-app state the panel header renders.
public struct AppDockState: Equatable, Sendable {
    public var appName: String?
    public var edge: String
    public var isDocked: Bool

    public init(appName: String? = nil, edge: String = "left", isDocked: Bool = false) {
        self.appName = appName
        self.edge = edge
        self.isDocked = isDocked
    }
}
