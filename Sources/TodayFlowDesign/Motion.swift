import Foundation

/// Which motion preference is active (mirrors the system Reduce Motion
/// setting; the app layer injects the live value).
public enum MotionPreference: String, Sendable, CaseIterable {
    case full
    case reduced
}

/// Motion parameters for the driver.md §4 animation set (checkmark draw-on
/// 250ms, row slide to Done, ring spring, confetti). Plain values rather than
/// `Animation`, so this type stays `Sendable` and testable without SwiftUI;
/// the view layer builds `Animation` from them. Under Reduce Motion every
/// animation collapses to its final state (nil = no animation).
public struct Motion: Sendable, Equatable {
    public enum Kind: String, Sendable, CaseIterable {
        case checkmark
        case rowSlide
        case ring
        case confetti
    }

    public let preference: MotionPreference
    public let checkmarkDuration: Double = 0.25
    public let rowSlideDuration: Double = 0.3
    public let ringResponse: Double = 0.45
    public let ringDamping: Double = 0.8
    public let confettiDuration: Double = 1.2

    public init(preference: MotionPreference) {
        self.preference = preference
    }

    /// Animation duration for a kind; nil when the user prefers reduced motion.
    public func duration(for kind: Kind) -> Double? {
        guard preference == .full else { return nil }
        switch kind {
        case .checkmark: return checkmarkDuration
        case .rowSlide: return rowSlideDuration
        case .ring: return ringResponse
        case .confetti: return confettiDuration
        }
    }

    /// Spring parameters (response, damping); only the ring uses a spring, and
    /// only under full motion.
    public func spring(for kind: Kind) -> (response: Double, damping: Double)? {
        guard preference == .full, kind == .ring else { return nil }
        return (response: ringResponse, damping: ringDamping)
    }
}
