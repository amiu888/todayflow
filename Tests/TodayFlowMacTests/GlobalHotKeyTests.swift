#if canImport(AppKit)
import Carbon
import Testing
import TodayFlowMac

struct GlobalHotKeyTests {
    /// FR-05: the default capture shortcut is ⌃⌥Space.
    @Test @MainActor
    func defaultShortcut_isControlOptionSpace() {
        #expect(GlobalHotKey.defaultKeyCode == 0x31)
        #expect(GlobalHotKey.defaultModifiers == UInt32(controlKey | optionKey))
    }
}
#endif
