import XCTest

final class FeatureRequestUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor private func openForm(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["workout-settings"].waitForExistence(timeout: 10))
        app.buttons["workout-settings"].tap()
        let link = app.buttons["request-feature"]
        for _ in 0..<4 where !link.isHittable { app.swipeUp() }
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        link.tap()
        XCTAssertTrue(app.textFields["feature-title"].waitForExistence(timeout: 5))
    }

    @MainActor private func fill(_ app: XCUIApplication, email: String) {
        app.textFields["feature-title"].tap()
        app.textFields["feature-title"].typeText("Repeat exercise blocks")
        app.toolbars.buttons["Done"].tap()
        let details = app.descendants(matching: .any).matching(identifier: "feature-details").firstMatch
        details.tap()
        details.typeText("Please let me repeat a group of exercises five times.")
        app.toolbars.buttons["Done"].tap()
        app.textFields["feature-email"].tap()
        if !email.isEmpty { app.textFields["feature-email"].typeText(email) }
        app.toolbars.buttons["Done"].tap()
        let send = app.buttons["send-feature-request"]
        for _ in 0..<3 where !send.isHittable { app.swipeUp() }
    }

    @MainActor private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor func testEmailValidationSuccessAndClearedDraft() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        openForm(app)
        capture("feature-request-empty")
        XCTAssertFalse(app.buttons["send-feature-request"].isEnabled)
        fill(app, email: "")
        XCTAssertFalse(app.buttons["send-feature-request"].isEnabled)
        app.textFields["feature-email"].tap()
        app.textFields["feature-email"].typeText("invalid-email")
        app.toolbars.buttons["Done"].tap()
        XCTAssertFalse(app.buttons["send-feature-request"].isEnabled)
        app.textFields["feature-email"].tap()
        app.textFields["feature-email"].typeText("@example.com")
        app.toolbars.buttons["Done"].tap()
        capture("feature-request-filled")
        app.buttons["send-feature-request"].tap()
        XCTAssertTrue(app.staticTexts["feature-request-received"].waitForExistence(timeout: 8))
        capture("feature-request-success")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "invalid-email@example.com")).firstMatch.exists)
        app.buttons["feature-request-done"].tap()
        app.buttons["request-feature"].tap()
        XCTAssertEqual(app.textFields["feature-title"].value as? String, "Give your idea a short title")
        XCTAssertEqual(app.textFields["feature-email"].value as? String, "you@example.com")
    }

    @MainActor func testRequiredEmailFailureRelaunchAndRetry() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-feature-request-fail-once"]
        app.launch()
        openForm(app)
        fill(app, email: "reply@example.com")
        XCTAssertTrue(app.buttons["send-feature-request"].isEnabled)
        app.buttons["send-feature-request"].tap()
        XCTAssertTrue(app.staticTexts["feature-error"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.textFields["feature-title"].isEnabled)
        capture("feature-request-retry")
        app.terminate()
        app.launchArguments = ["-ui-testing", "-preserve-feature-request"]
        app.launch()
        openForm(app)
        XCTAssertEqual(app.textFields["feature-title"].value as? String, "Repeat exercise blocks")
        let send = app.buttons["send-feature-request"]
        for _ in 0..<3 where !send.isHittable { app.swipeUp() }
        send.tap()
        XCTAssertTrue(app.staticTexts["feature-request-received"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "reply@example.com")).firstMatch.exists)
    }
}
