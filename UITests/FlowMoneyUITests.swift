import XCTest

/// Critical-path UI tests. Each launch uses `-uiTesting`: demo data, in-memory storage, clean defaults.
@MainActor
final class FlowMoneyUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()
    }

    private func startDemo() {
        let demo = app.buttons["onboarding.demo"]
        XCTAssertTrue(demo.waitForExistence(timeout: 10))
        demo.tap()
        XCTAssertTrue(app.buttons["home.action.expense"].waitForExistence(timeout: 10))
    }

    func testDemoShowsDashboard() {
        startDemo()
        XCTAssertTrue(app.staticTexts["Total balance"].exists)
        XCTAssertTrue(app.staticTexts["Recent transactions"].exists)
    }

    func testAddExpenseAppearsInActivity() {
        startDemo()
        app.buttons["home.action.expense"].tap()

        for key in ["4", "2", "decimal", "5", "0"] {
            app.buttons["keypad.\(key)"].tap()
        }
        app.buttons["editor.category"].tap()
        let food = app.buttons["category.food"]
        XCTAssertTrue(food.waitForExistence(timeout: 5))
        food.tap()

        let merchant = app.textFields["editor.merchant"]
        merchant.tap()
        merchant.typeText("UI Test Bistro")
        app.toolbars.buttons["Done"].firstMatch.tap()

        let save = app.buttons["editor.save"]
        XCTAssertTrue(save.isEnabled)
        save.tap()

        app.tabBars.buttons["Activity"].tap()
        XCTAssertTrue(app.staticTexts["UI Test Bistro"].waitForExistence(timeout: 5))
    }

    func testSaveIsDisabledUntilFormIsValid() {
        startDemo()
        app.buttons["home.action.expense"].tap()
        let save = app.buttons["editor.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertFalse(save.isEnabled, "no amount, no category")
        app.buttons["keypad.7"].tap()
        XCTAssertFalse(save.isEnabled, "still no category")
    }

    func testEveryTabLoads() {
        startDemo()
        for tab in ["Activity", "Plan", "Insights", "Profile", "Home"] {
            app.tabBars.buttons[tab].tap()
            XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 5) || tab == "Home")
        }
        app.tabBars.buttons["Plan"].tap()
        XCTAssertTrue(app.buttons["plan.budgets"].waitForExistence(timeout: 5))
    }

    func testExitDemoReturnsToOnboarding() {
        startDemo()
        app.tabBars.buttons["Profile"].tap()
        let signOut = app.buttons["profile.signOut"]
        // The button is the last row of a lazy list: scroll until it's rendered.
        for _ in 0 ..< 4 where !signOut.exists {
            app.swipeUp()
        }
        XCTAssertTrue(signOut.waitForExistence(timeout: 5))
        signOut.tap()
        let confirm = app.buttons["profile.confirmSignOut"].firstMatch // iOS 26 dialogs expose the action twice
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(app.buttons["onboarding.demo"].waitForExistence(timeout: 5))
    }
}
