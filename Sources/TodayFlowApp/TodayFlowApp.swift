import Foundation
#if canImport(AppKit)
import AppKit
import TodayFlowMac

@main
enum TodayFlowApp {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        // Kept alive for the whole run: `NSApplication.delegate` is a weak
        // reference, so the app would lose its delegate (and its environment)
        // on the next runloop cycle without this strong local.
        let delegate = TodayFlowApplicationDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }
}
#else
@main
enum TodayFlowApp {
    static func main() {
        FileHandle.standardError.write(Data("TodayFlow requires macOS.\n".utf8))
        exit(1)
    }
}
#endif
