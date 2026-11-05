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
        // Every UI test gets a clean database; never touch the user's tasks.
        let db = FileManager.default.temporaryDirectory
            .appendingPathComponent("todayflow-uitest-\(UUID().uuidString).sqlite")
        app.launchEnvironment["TODAYFLOW_DB_PATH"] = db.path
        // Floating, non-activating panels are invisible to XCUITest's window
        // snapshot on current macOS; host the same views in normal windows.
        app.launchEnvironment["TODAYFLOW_UI_TESTING"] = "1"
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

        let title = app.textFields["Title"]
        XCTAssertTrue(
            title.waitForExistence(timeout: 5),
            "Capture Clipboard did not open the quick-add sheet"
        )
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

    /// Double-clicking a tray opens its full window, and multiple tray windows
    /// can be open at once.
    func testTrayWindowsOpenForMultipleTrays() throws {
        let app = launchApp()
        app.activate()

        let working = app.descendants(matching: .any)
            .matching(identifier: "tray-name-Working tray").firstMatch
        XCTAssertTrue(working.waitForExistence(timeout: 5))
        working.doubleClick()
        XCTAssertTrue(
            app.windows["Tray · Working tray"].waitForExistence(timeout: 5),
            "Double-click on a tray did not open its window"
        )
        app.buttons["Add working tray"].click()
        let name = app.textFields["Tray name"]
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        name.typeText("Second tray")
        app.buttons["Create"].click()

        let second = app.descendants(matching: .any)
            .matching(identifier: "tray-name-Second tray").firstMatch
        XCTAssertTrue(second.waitForExistence(timeout: 4))
        second.doubleClick()
        XCTAssertTrue(
            app.windows["Tray · Second tray"].waitForExistence(timeout: 5),
            "The second tray window did not open"
        )
        XCTAssertTrue(app.windows["Tray · Working tray"].exists)
    }

    /// Moving a task changes its position in the list.
    func testContextMenuMoveDownReordersTasks() throws {
        let app = launchApp()
        app.activate()

        func create(_ title: String) {
            app.typeKey("n", modifierFlags: .command)
            let field = app.textFields["Title"]
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            app.typeText(title)
            app.buttons["Add task"].click()

            // Wait for the capture sheet to close before the next interaction.
            let deadline = Date().addingTimeInterval(5)
            while field.exists, Date() < deadline {
                Thread.sleep(forTimeInterval: 0.1)
            }
            Thread.sleep(forTimeInterval: 0.4)

            XCTAssertTrue(
                app.descendants(matching: .any)
                    .matching(NSPredicate(format: "label CONTAINS %@", title))
                    .firstMatch
                    .waitForExistence(timeout: 8)
            )
        }

        create("Move A")
        create("Move B")

        let rowB = app.descendants(matching: .any)
            .matching(identifier: "task-row-Move B").firstMatch
        let rowA = app.descendants(matching: .any)
            .matching(identifier: "task-row-Move A").firstMatch
        XCTAssertTrue(rowB.waitForExistence(timeout: 5))
        XCTAssertTrue(rowA.waitForExistence(timeout: 5))

        // New captures insert on top: B is above A. Move B down.
        let bAboveA = rowB.frame.minY < rowA.frame.minY
        app.activate()
        let moveDown = app.descendants(matching: .any)
            .matching(identifier: "move-down-Move B").firstMatch
        XCTAssertTrue(moveDown.waitForExistence(timeout: 3))
        moveDown.click()

        var movedBelow = false
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            let b = app.descendants(matching: .any)
                .matching(identifier: "task-row-Move B").firstMatch
            let a = app.descendants(matching: .any)
                .matching(identifier: "task-row-Move A").firstMatch
            if b.exists, a.exists, b.frame.minY > a.frame.minY {
                movedBelow = true
                break
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTAssertTrue(bAboveA && movedBelow, "Move down did not change the list order")
    }

    /// A single click on a task opens its detail window.
    func testClickingTaskOpensDetailWindow() throws {
        let app = launchApp()
        app.activate()
        app.typeKey("n", modifierFlags: .command)

        let taskTitle = "Detail test \(UUID().uuidString.prefix(6))"
        let title = app.textFields["Title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        app.typeText(taskTitle)

        app.buttons["Add task"].click()
        let deadline = Date().addingTimeInterval(5)
        while title.exists, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }
        Thread.sleep(forTimeInterval: 0.5)

        let row = app.descendants(matching: .any)
            .matching(identifier: "task-row-\(taskTitle)").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 8))

        // The first click on a window that lost key status only activates it;
        // retry once before failing.
        app.windows["Today"]
            .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.02))
            .click()
        row.click()
        if !app.windows["Task"].waitForExistence(timeout: 3) {
            row.click()
        }

        XCTAssertTrue(
            app.windows["Task"].waitForExistence(timeout: 5),
            "Clicking a task did not open the detail window"
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
