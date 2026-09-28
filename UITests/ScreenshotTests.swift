import XCTest

/// Captures the key screens (light + dark) as test attachments — the App Store / portfolio screenshots
/// are produced by this test, so they always show the current build. `make screenshots` exports them.
@MainActor
final class ScreenshotTests: XCTestCase {
    func testCaptureLight() {
        capture(dark: false)
    }

    func testCaptureDark() {
        capture(dark: true)
    }

    private func capture(dark: Bool) {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"] + (dark ? ["-uiDark"] : [])
        app.launch()
        let prefix = dark ? "dark" : "light"

        snap(app, "\(prefix)-01-onboarding")
        app.buttons["onboarding.demo"].tap()
        XCTAssertTrue(app.buttons["home.action.expense"].waitForExistence(timeout: 10))
        sleep(1)
        snap(app, "\(prefix)-02-home")

        app.buttons["home.action.expense"].tap()
        for key in ["1", "8", "decimal", "4", "0"] {
            app.buttons["keypad.\(key)"].tap()
        }
        snap(app, "\(prefix)-03-add-expense")
        app.buttons["Cancel"].firstMatch.tap()
        if app.buttons["Cancel"].exists {
            app.swipeDown(velocity: .fast)
        }

        app.tabBars.buttons["Activity"].tap()
        sleep(1)
        snap(app, "\(prefix)-04-transactions")

        app.tabBars.buttons["Plan"].tap()
        sleep(1)
        snap(app, "\(prefix)-05-plan")
        app.buttons["plan.budgets"].tap()
        sleep(1)
        snap(app, "\(prefix)-06-budgets")

        app.tabBars.buttons["Insights"].tap()
        sleep(1)
        snap(app, "\(prefix)-07-insights")
        app.buttons["insights.analytics"].tap()
        sleep(1)
        snap(app, "\(prefix)-08-analytics")

        app.tabBars.buttons["Profile"].tap()
        sleep(1)
        snap(app, "\(prefix)-09-profile")
    }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
