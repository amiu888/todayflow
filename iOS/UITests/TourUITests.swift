import XCTest

/// Scripted walkthroughs for the website's tutorial videos and screenshots.
/// Each test is one clip: `site-work/record-ios.sh <test>` records the
/// simulator while it runs. They also double as smoke tests of the main flows.
///
/// The pauses are for viewers, not for the app: keep them.
@MainActor
final class TourUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-seedSample", "-noNotificationPrompt", "YES"]
        if name.contains("Sync") { app.launchArguments += ["-tab", "settings"] }
        if let tab = ProcessInfo.processInfo.environment["TOUR_TAB"] {
            app.launchArguments += ["-tab", tab]
        }
        app.launch()
        _ = app.staticTexts["Today"].firstMatch.waitForExistence(timeout: 10)
        pause(1.5)
    }

    private func pause(_ seconds: Double) {
        Thread.sleep(forTimeInterval: seconds)
    }

    /// Types like a person, so viewers can read along.
    private func slowType(_ text: String, into element: XCUIElement, perKey: Double = 0.07) {
        for character in text {
            app.typeText(String(character))
            Thread.sleep(forTimeInterval: perKey)
        }
    }

    private func row(_ title: String) -> XCUIElement {
        app.staticTexts[title].firstMatch
    }

    // MARK: - Clips

    /// 1 · Add a task in plain words.
    func test1AddTask() {
        app.buttons["New Task"].firstMatch.tap()
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        pause(0.8)
        slowType("Call Maria tomorrow 3pm #Q4", into: field)
        pause(2.0)
        app.buttons["Add"].firstMatch.tap()
        pause(1.5)
        // Tomorrow in the week strip shows the new task.
        let tomorrow = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", tomorrowLabel())).firstMatch
        if tomorrow.exists { tomorrow.tap(); pause(2.5) }
        let back = app.buttons["Back to Today"].firstMatch
        if back.exists { back.tap() } else { tomorrow.exists ? app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", todayLabel())).firstMatch.tap() : () }
        pause(1.5)
    }

    /// 2 · Finish things: swipe to complete, undo, open a task's story.
    func test2CompleteAndDetail() {
        let call = row("Call supplier")
        XCTAssertTrue(call.waitForExistence(timeout: 5))
        call.swipeRight()
        pause(0.6)
        if app.buttons["Complete"].firstMatch.exists { app.buttons["Complete"].firstMatch.tap() }
        pause(2.0)
        row("Review Q4 roadmap").tap()
        pause(2.0)
        app.swipeUp()
        pause(1.0)
        let note = app.textFields["Add a note…"].firstMatch
        if note.waitForExistence(timeout: 3) {
            note.tap()
            slowType("Draft sent to Maria for comments", into: note)
            pause(0.6)
            app.buttons["Send"].firstMatch.tap()
            pause(1.5)
        }
        app.swipeDown()
        pause(1.5)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        pause(1.5)
    }

    /// 3 · Plan the week and month.
    func test3Calendar() {
        app.buttons["Calendar"].firstMatch.tap()
        pause(2.0)
        let days = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", ", ")).allElementsBoundByIndex
        if days.count > 4 { days[4].tap(); pause(2.0) }
        app.buttons["Month"].firstMatch.tap()
        pause(2.5)
        app.buttons["Next"].firstMatch.tap()
        pause(1.5)
        app.buttons["Previous"].firstMatch.tap()
        pause(1.5)
        app.buttons["Week"].firstMatch.tap()
        pause(1.5)
    }

    /// 4 · Find anything.
    func test4Search() {
        app.buttons["Search"].firstMatch.tap()
        pause(1.2)
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        slowType("#Q4", into: field, perKey: 0.15)
        pause(2.5)
        field.typeText(XCUIKeyboardKey.delete.rawValue)
        field.typeText(XCUIKeyboardKey.delete.rawValue)
        field.typeText(XCUIKeyboardKey.delete.rawValue)
        slowType("flights", into: field)
        pause(2.5)
    }

    /// 5 · Connect to your own server (fields only; the address is an example).
    func test5SyncSettings() {
        pause(1.0)
        let server = app.textFields.element(boundBy: 0)
        if server.waitForExistence(timeout: 5) {
            server.tap()
            slowType("https://nas.example.ts.net", into: server, perKey: 0.05)
            pause(0.8)
            let code = app.textFields.element(boundBy: 1)
            code.tap()
            slowType("1a2b3c-4d5e6f-7a8b9c-0d1e2f", into: code, perKey: 0.04)
            pause(3.0)
        }
    }

    /// 6 · Share a web page from Safari into TodayFlow.
    func test6ShareFromSafari() {
        let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        safari.launch()
        _ = safari.wait(for: .runningForeground, timeout: 10)
        pause(2.0)
        // A neutral demo page served from the Mac (site-work/demo-page).
        let address = safari.textFields.firstMatch
        if address.waitForExistence(timeout: 5) {
            address.tap()
            address.typeText("http://127.0.0.1:8099/\n")
        }
        pause(3.0)
        // iOS 26 Safari keeps Share in the page menu.
        let menu = safari.buttons["MoreMenuButton"].firstMatch
        if menu.waitForExistence(timeout: 5) { menu.tap() }
        pause(1.2)
        let share = safari.buttons["Share"].firstMatch
        if share.waitForExistence(timeout: 5) { share.tap() }
        pause(2.0)
        let target = safari.buttons["TodayFlow"].firstMatch
        if !target.waitForExistence(timeout: 4) {
            for b in safari.buttons.allElementsBoundByIndex { print("SHARE-BTN id=\(b.identifier) label=\(b.label)") }
            for c in safari.cells.allElementsBoundByIndex { print("SHARE-CELL id=\(c.identifier) label=\(c.label)") }
        }
        if target.waitForExistence(timeout: 2) {
            target.tap()
            pause(2.5)
            let add = safari.buttons["Add"].firstMatch
            if add.waitForExistence(timeout: 5) { add.tap() }
            pause(1.5)
        }
        app.activate()
        pause(3.0)
    }

    // MARK: - Helpers

    private func tomorrowLabel() -> String {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: .now)!
        return tomorrow.formatted(date: .complete, time: .omitted)
    }

    private func todayLabel() -> String {
        Date.now.formatted(date: .complete, time: .omitted)
    }
}
