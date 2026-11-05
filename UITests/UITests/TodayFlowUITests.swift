import XCTest
import AppKit

/// Real UI tests against the built TodayFlow.app bundle
/// (`com.todayflow.app`). Run via `scripts/run-ui-tests.sh`.
final class TodayFlowUITests: XCTestCase {
    private static let png = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
    )!

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "com.todayflow.app")
        app.launch()
        app.activate()
        let appeared = app.windows.firstMatch.waitForExistence(timeout: 15)
        if !appeared {
            print("APP STATE: \(app.state.rawValue)")
            print("APP TREE:\n\(app.debugDescription)")
        }
        XCTAssertTrue(appeared, "TodayFlow did not show its panel")
        return app
    }

    /// Paste a real PNG into the Today panel, then click Add. This exercises
    /// the same NSPasteboard/NSItemProvider → capture sheet → save path as a
    /// drag, without needing cross-process drag automation.
    func testPastePNGAndAddCreatesATask() throws {
        let app = launchApp()

        NSPasteboard.general.clearContents()
        XCTAssertTrue(NSPasteboard.general.setData(Self.png, forType: .png))

        app.activate()
        app.menuBars.menuBarItems["File"].click()
        let capture = app.menuItems["Capture Clipboard"]
        XCTAssertTrue(capture.waitForExistence(timeout: 3))
        capture.click()

        XCTAssertTrue(
            app.staticTexts["New task"].waitForExistence(timeout: 5),
            "Capture Clipboard did not open the quick-add sheet"
        )

        let title = app.textFields["Title"]
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        app.typeText("UI test image")

        let add = app.buttons["Add task"]
        XCTAssertTrue(add.waitForExistence(timeout: 3), "Add button missing")
        add.click()

        let saved = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS 'UI test image'")
        ).firstMatch
        XCTAssertTrue(
            saved.waitForExistence(timeout: 8),
            "The captured image task did not appear in Today"
        )
    }

    /// The empty quick-add sheet can be opened with the global hotkey and
    /// saved. This verifies keyboard capture and the title/Add controls.
    func testGlobalHotkeyOpensCaptureAndSavingShowsTask() throws {
        let app = launchApp()
        app.activate()

        app.typeKey("n", modifierFlags: .command)

        let title = app.textFields["Title"]
        XCTAssertTrue(
            title.waitForExistence(timeout: 5),
            "⌘N did not open the capture sheet"
        )

        title.click()
        title.typeText("UI test task")

        let add = app.buttons["Add task"]
        XCTAssertTrue(add.waitForExistence(timeout: 2))
        add.click()

        let saved = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS 'UI test task'")
        ).firstMatch
        XCTAssertTrue(
            saved.waitForExistence(timeout: 8),
            "The new task did not appear in the Today list"
        )
    }
}
