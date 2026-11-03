import SwiftUI

/// Design tokens shared by every TodayFlow surface (driver.md §4).
public enum DesignTokens {
    /// Window mode sizes (driver.md §4: Panel 360×640 min 300×420, Slim bar
    /// 360×44, menu bar popover 340×480, Detail 720×640).
    public enum Window {
        public static let panel = CGSize(width: 360, height: 640)
        public static let panelMinimum = CGSize(width: 300, height: 420)
        public static let slimBar = CGSize(width: 360, height: 44)
        public static let menuBar = CGSize(width: 340, height: 480)
        public static let detail = CGSize(width: 720, height: 640)
    }

    /// Header progress ring geometry — a thin mark: 2.5pt stroke on a 28pt ring.
    public enum Ring {
        public static let diameter: CGFloat = 28
        public static let lineWidth: CGFloat = 2.5
    }

    /// Row and section metrics (driver.md §4 row spec).
    public enum Spacing {
        public static let rowHeight: CGFloat = 44
        public static let cornerRadius: CGFloat = 10
        public static let sectionGap: CGFloat = 8
    }
}

extension Color {
    /// A color from a `#rrggbb` hex string. Invalid input resolves to gray
    /// rather than crashing — design tokens are data, not code paths.
    public init(hex: String) {
        var digits = hex
        if digits.hasPrefix("#") {
            digits.removeFirst()
        }
        guard digits.count == 6, let value = UInt64(digits, radix: 16) else {
            self = .gray
            return
        }
        self = Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
