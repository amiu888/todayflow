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

    /// Dragging a task row onto a working tray adds it to that tray.
    func testDraggingTaskIntoWorkingTrayAddsIt() throws {
        let app = launchApp()
        app.activate()
        app.typeKey("n", modifierFlags: .command)

        let title = app.textFields["Title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        app.typeText("Tray drag test")
        app.buttons["Add task"].click()

        let row = app.descendants(matching: .any).matching(identifier: "task-row-Tray drag test").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 8), "Task row missing")

        let tray = app.descendants(matching: .any).matching(identifier: "tray-Working tray").firstMatch
        XCTAssertTrue(tray.waitForExistence(timeout: 5), "Working tray missing")

        row.press(forDuration: 0.8, thenDragTo: tray)

        let chip = app.descendants(matching: .any).matching(identifier: "tray-chip-Tray drag test").firstMatch
        XCTAssertTrue(
            chip.waitForExistence(timeout: 6),
            "The task was not added to the working tray by drag and drop"
        )
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

        let title = app.textFields["Title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        app.typeText("Detail test task")

        app.buttons["Add task"].click()

        let row = app.descendants(matching: .any)
            .matching(identifier: "task-row-Detail test task").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 8))
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.4)).click()

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
