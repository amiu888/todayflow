import AppKit
import SwiftUI

extension View {
    /// Lets people resize the sheet or window this view is in, down to its
    /// smallest usable size. SwiftUI sheets on macOS otherwise keep one size.
    func resizableWindow() -> some View {
        background(ResizableWindowEnabler())
    }
}

private struct ResizableWindowEnabler: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { EnablerView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class EnablerView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, !window.styleMask.contains(.resizable) else { return }
            window.styleMask.insert(.resizable)
        }
    }
}
