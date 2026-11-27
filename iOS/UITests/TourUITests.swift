import UIKit
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
        app.launchArguments = ["-resetData", "-seedSample", "-noNotificationPrompt", "YES"]
        if name.contains("Sync") { app.launchArguments += ["-tab", "settings"] }
        if name.contains("TraysTab") { app.launchArguments += ["-tab", "trays"] }
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
        let share = safari.descendants(matching: .any).matching(NSPredicate(format: "label == 'Share'")).firstMatch
        if share.waitForExistence(timeout: 5) { share.tap() }
        pause(2.0)
        let target = safari.cells.matching(identifier: "shareCell").matching(NSPredicate(format: "label == 'TodayFlow'")).firstMatch
        if target.waitForExistence(timeout: 6) {
            target.tap()
            pause(2.5)
            let add = safari.buttons["Add"].firstMatch
            if add.waitForExistence(timeout: 5) { add.tap() }
            pause(1.5)
        }
        app.activate()
        pause(3.0)
    }

    /// 7 · Trays: put tasks in play, open the tray, make a new one.
    func test7Trays() {
        let roadmap = row("Review Q4 roadmap")
        XCTAssertTrue(roadmap.waitForExistence(timeout: 5))
        roadmap.press(forDuration: 1.0)
        pause(1.0)
        app.buttons["Add to Tray"].firstMatch.tap()
        pause(0.8)
        app.buttons["Working tray"].firstMatch.tap()
        pause(1.5)
        let budget = row("Budget draft")
        budget.press(forDuration: 1.0)
        pause(0.8)
        app.buttons["Add to Tray"].firstMatch.tap()
        pause(0.6)
        app.buttons["Working tray"].firstMatch.tap()
        pause(1.5)
        let chip = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Working tray tray'")).firstMatch
        XCTAssertTrue(chip.waitForExistence(timeout: 3))
        XCTAssertTrue(chip.label.contains("2 tasks"), "chip: \(chip.label)")
        chip.tap()
        pause(2.0)
        XCTAssertTrue(app.staticTexts["Review Q4 roadmap"].exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        pause(1.0)
        app.buttons["New tray"].firstMatch.tap()
        pause(0.8)
        app.typeText("Errands")
        pause(0.6)
        app.alerts.buttons["Add"].tap()
        pause(2.0)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Errands tray'")).firstMatch.exists)
    }

    /// 8 · The Trays tab: every tray and its tasks; make a new one and open it.
    func test8TraysTab() {
        XCTAssertTrue(app.navigationBars["Trays"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Working tray tray'")).firstMatch.exists)
        pause(1.0)
        let add = app.buttons["New Tray"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 3))
        add.tap()
        app.typeText("Waiting on others")
        app.alerts.buttons["Add"].tap()
        pause(1.5)
        let tray = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Waiting on others tray'")).firstMatch
        XCTAssertTrue(tray.waitForExistence(timeout: 3))
        tray.tap()
        XCTAssertTrue(app.navigationBars["Waiting on others"].waitForExistence(timeout: 3))
        pause(1.5)
    }

    /// 9 · Paste a chat screenshot: it's read on the iPhone, titled, and its
    /// to-dos become the new task's checklist.
    func test9PasteScreenshot() {
        UIPasteboard.general.image = Self.chatScreenshot([
            "Maria: Can you book the dentist",
            "Please renew the parking permit",
        ])
        app.buttons["New Task"].firstMatch.tap()
        let paste = app.buttons["Paste"].firstMatch
        XCTAssertTrue(paste.waitForExistence(timeout: 5))
        pause(0.8)
        paste.tap()
        // Allow Paste, if iOS asks.
        let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Allow Paste"]
        if allow.waitForExistence(timeout: 2) { allow.tap() }

        XCTAssertTrue(app.staticTexts["To-dos found"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] 'dentist'")).firstMatch.exists)
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] 'parking permit'")).firstMatch.exists)
        let title = app.textFields.firstMatch.value as? String ?? ""
        XCTAssertFalse(title.isEmpty, "the screenshot names the task")
        XCTAssertFalse(title.hasPrefix("CHG"), "no made-up ticket number: \(title)")
        pause(1.5)
        app.buttons["Add"].firstMatch.tap()
        pause(1.0)

        // The new task carries the screenshot and the checklist.
        let created = app.staticTexts.matching(NSPredicate(format: "label == %@", title)).firstMatch
        for _ in 0..<6 where !created.isHittable { app.swipeUp() }
        XCTAssertTrue(created.exists, "the new task is on Today")
        if created.exists {
            created.tap()
            XCTAssertTrue(app.staticTexts["Checklist"].waitForExistence(timeout: 5)
                          || app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Checklist'")).firstMatch.exists)
            XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] 'dentist'")).firstMatch.waitForExistence(timeout: 5))
            app.swipeUp()
            XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Find To-dos'")).firstMatch.waitForExistence(timeout: 3))
            pause(2.0)
        }
    }

    // MARK: - Helpers

    private static func chatScreenshot(_ lines: [String]) -> UIImage {
        let size = CGSize(width: 1000, height: 110 * lines.count + 60)
        return UIGraphicsImageRenderer(size: size).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            for (index, line) in lines.enumerated() {
                (line as NSString).draw(at: CGPoint(x: 30, y: 30 + index * 110), withAttributes: [
                    .font: UIFont.systemFont(ofSize: 48), .foregroundColor: UIColor.black,
                ])
            }
        }
    }

    private func tomorrowLabel() -> String {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: .now)!
        return tomorrow.formatted(date: .complete, time: .omitted)
    }

    private func todayLabel() -> String {
        Date.now.formatted(date: .complete, time: .omitted)
    }
}
