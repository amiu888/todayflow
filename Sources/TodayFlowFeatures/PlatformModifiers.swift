import SwiftUI
#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif

public extension View {
    /// Esc cancels: `onExitCommand` on the Mac; on iPhone and iPad, Escape
    /// from a hardware keyboard.
    func onEscape(perform action: @escaping () -> Void) -> some View {
        #if os(macOS)
        return onExitCommand(perform: action)
        #else
        return onKeyPress(.escape) {
            action()
            return .handled
        }
        #endif
    }
}

public extension View {
    /// `.link` on the Mac; a plain borderless button on iPhone.
    @ViewBuilder
    func linkButtonStyle() -> some View {
        #if os(macOS)
        buttonStyle(.link)
        #else
        buttonStyle(.borderless)
        #endif
    }

    /// A checkbox on the Mac; a switch on iPhone.
    @ViewBuilder
    func checkboxToggleStyle() -> some View {
        #if os(macOS)
        toggleStyle(.checkbox)
        #else
        toggleStyle(.switch)
        #endif
    }

    /// The Mac's borderless menu button; the default menu style on iPhone.
    @ViewBuilder
    func borderlessMenuStyle() -> some View {
        #if os(macOS)
        menuStyle(.borderlessButton)
        #else
        menuStyle(.button).buttonStyle(.borderless)
        #endif
    }

    /// Radio buttons on the Mac; an inline list on iPhone.
    @ViewBuilder
    func radioGroupPickerStyle() -> some View {
        #if os(macOS)
        pickerStyle(.radioGroup)
        #else
        pickerStyle(.inline)
        #endif
    }
}

/// Plain-text copy that works on the Mac and on iPhone.
public enum PlatformClipboard {
    @MainActor
    public static func copy(_ text: String) {
        #if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }
}
