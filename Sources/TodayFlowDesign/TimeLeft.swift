import Foundation

/// Compact "time left" formatting for the header (driver.md §4: "4 left ·
/// 2h 10m"). Rounds to the nearest minute; anything under a minute reads as
/// "now".
public enum TimeLeft {
    public static func format(_ interval: TimeInterval) -> String {
        let minutes = Int((interval / 60).rounded())
        guard minutes >= 1 else { return "now" }
        guard minutes >= 60 else { return "\(minutes)m" }
        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? "\(hours)h" : "\(hours)h \(remainder)m"
    }
}
