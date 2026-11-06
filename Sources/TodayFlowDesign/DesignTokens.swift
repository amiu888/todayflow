import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

/// Design tokens shared by every TodayFlow surface (driver.md §4).
///
/// "Cinematic daylight": near-black indigo by default, with a white/slate
/// light theme. The memorable gesture is the sky→royal→violet aurora behind
/// the day header; lists and controls stay quiet around it.
public enum DesignTokens {
    public enum Palette {
        public static let background = adaptive(light: "#F7F9FF", dark: "#07090F")
        public static let surface = adaptive(light: "#FFFFFF", dark: "#151F2E")
        public static let surfaceRaised = adaptive(light: "#F1F5F9", dark: "#1B2739")
        public static let textPrimary = adaptive(light: "#0F172A", dark: "#F1F5F9")
        public static let textSecondary = adaptive(light: "#475569", dark: "#94A3B8")

        public static let accent = adaptive(light: "#2563EB", dark: "#60A5FA")
        public static let accentStrong = adaptive(light: "#1D4ED8", dark: "#818CF8")
        public static let violet = adaptive(light: "#7C3AED", dark: "#A78BFA")
        public static let accentSoft = accent.opacity(0.14)

        public static let success = adaptive(light: "#059669", dark: "#34D399")
        public static let warning = adaptive(light: "#D97706", dark: "#FBBF24")
        public static let danger = adaptive(light: "#DC2626", dark: "#F87171")
        public static let urgent = danger

        public static let hairline = adaptive(light: "#E2E8F0", dark: "#263449")
        public static let shadow = Color.black.opacity(0.35)

        /// The brand gesture: sky → royal → violet.
        public static let gradient = LinearGradient(
            colors: [accent, accentStrong, violet],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        /// A soft aurora used once, behind the day header.
        public static let aurora = LinearGradient(
            colors: [
                accent.opacity(0.22),
                accentStrong.opacity(0.12),
                violet.opacity(0.10),
                .clear,
            ],
            startPoint: .topLeading,
            endPoint: .center
        )

        private static func adaptive(light: String, dark: String) -> Color {
            #if canImport(AppKit)
            return Color(nsColor: NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                return NSColor(todayFlowHex: isDark ? dark : light) ?? .labelColor
            })
            #else
            return Color(hex: light)
            #endif
        }
    }

    /// Working-tray identity. Apple’s SF Symbols supply the tray glyph so it
    /// matches the native macOS visual language.
    public enum TrayPalette {
        public static let iconName = "tray.full.fill"
        public static let colors: [String] = [
            "#60A5FA", // sky
            "#A78BFA", // violet
            "#34D399", // mint
            "#FBBF24", // amber
            "#FB7185", // coral
            "#22D3EE", // cyan
            "#F472B6", // rose
            "#94A3B8", // slate
        ]

        public static func colorHex(at index: Int) -> String {
            colors[((index % colors.count) + colors.count) % colors.count]
        }
    }

    /// Window mode sizes (driver.md §4: Panel 360×640 min 300×420, Slim bar
    /// 360×44, menu bar popover 340×480, Detail 720×640, Hierarchy 640×560,
    /// Settings 480×560).
    public enum Window {
        public static let panel = CGSize(width: 360, height: 640)
        public static let panelMinimum = CGSize(width: 320, height: 420)
        public static let slimBar = CGSize(width: 360, height: 44)
        public static let menuBar = CGSize(width: 340, height: 480)
        /// The quick-add capture panel (FR-02/FR-05); width matches the panel.
        public static let capture = CGSize(width: 400, height: 520)
        public static let detail = CGSize(width: 720, height: 640)
        public static let hierarchy = CGSize(width: 640, height: 560)
        public static let calendar = CGSize(width: 780, height: 600)
        public static let upcoming = CGSize(width: 420, height: 520)
        public static let completed = CGSize(width: 420, height: 520)
        public static let settings = CGSize(width: 480, height: 560)
        public static let contacts = CGSize(width: 760, height: 600)
        public static let contactsMinimum = CGSize(width: 580, height: 420)
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

#if canImport(AppKit)
extension NSColor {
    convenience init?(todayFlowHex hex: String) {
        var digits = hex
        if digits.hasPrefix("#") { digits.removeFirst() }
        guard digits.count == 6, let value = UInt64(digits, radix: 16) else {
            return nil
        }
        self.init(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}
#endif

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
