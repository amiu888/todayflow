import SwiftUI
import TodayFlowCore

/// Priority dot colors (driver.md §4 row spec: "P1 red, P2 orange, P3 yellow,
/// P4 grey").
///
/// This is a *status* scale, not a categorical one, so it follows the data-viz
/// method's status rules rather than the categorical gates: the three colored
/// steps are the reference palette's fixed, validated status steps (critical /
/// serious / warning) and are intentionally mode-invariant; only the neutral
/// step (P4) steps per color scheme.
///
/// Validation (validate_palette.js, per-color contrast against the reference
/// surfaces `#fcfcfb` light / `#1a1a19` dark):
/// - `#d03b3b` critical  4.68:1 light / 3.62:1 dark
/// - `#ec835a` serious   2.57:1 light / 6.60:1 dark
/// - `#fab219` warning   1.79:1 light / 9.49:1 dark
/// - `#8e8e93` neutral   3.18:1 light / 5.34:1 dark (light step)
/// - `#98989d` neutral   2.80:1 light / 6.07:1 dark (dark step)
///
/// The sub-3:1 values on the light surface are the method's documented
/// conditional relax: a status color never carries meaning alone — the dot
/// ships with its label (hover quick action, detail view, VoiceOver), so the
/// color is redundant with the label, never the only cue.
public enum PriorityColor {
    public static func hex(for priority: Priority, in scheme: ColorScheme) -> String {
        switch priority {
        case .urgent: return "#d03b3b"
        case .high: return "#ec835a"
        case .normal: return "#fab219"
        case .low: return scheme == .dark ? "#98989d" : "#8e8e93"
        }
    }

    public static func color(for priority: Priority, in scheme: ColorScheme) -> Color {
        Color(hex: hex(for: priority, in: scheme))
    }
}
