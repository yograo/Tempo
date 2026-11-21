import XCTest

final class TempoUITests: XCTestCase {
    @MainActor
    private func launch() -> XCUIApplication {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        return app
    }

    @MainActor
    func testVisualTour() {
        let app = launch()
        XCTAssertTrue(app.buttons["create-routine"].waitForExistence(timeout: 5))
        capture(app, name: "01-library")
        app.buttons["routine-Everyday energy"].tap()
        XCTAssertTrue(app.buttons["start-routine"].waitForExistence(timeout: 3))
        capture(app, name: "02-routine")
        app.buttons["start-routine"].tap()
        XCTAssertTrue(app.staticTexts["current-step"].waitForExistence(timeout: 10))
        capture(app, name: "03-countdown")
        app.buttons["pause-resume"].tap()
        app.buttons["skip-step"].tap()
        capture(app, name: "04-rest")
        for _ in 0..<6 { app.buttons["skip-step"].tap() }
        XCTAssertTrue(app.staticTexts["You showed up."].waitForExistence(timeout: 3))
        capture(app, name: "05-complete")
        app.buttons["finish-workout"].tap()
        XCTAssertTrue(app.buttons["start-routine"].waitForExistence(timeout: 3))
        expectation(for: NSPredicate { _, _ in app.frame.width < app.frame.height }, evaluatedWith: app)
        waitForExpectations(timeout: 5)
        app.buttons["Routine options"].tap()
        XCTAssertTrue(app.buttons["Edit routine"].waitForExistence(timeout: 3))
        app.buttons["Edit routine"].tap()
        XCTAssertTrue(app.textFields["routine-name"].waitForExistence(timeout: 3))
        capture(app, name: "06-editor")
    }

    @MainActor
    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testCreatePersistEditAndDeleteRoutine() {
        let app = launch()
        app.buttons["create-routine"].tap()
        XCTAssertFalse(app.buttons["save-routine"].isEnabled)
        app.textFields["routine-name"].tap()
        app.textFields["routine-name"].typeText("Evening reset\n")
        addStep(app, name: "Stretch", rest: false, seconds: "30 sec")
        addStep(app, name: nil, rest: true, seconds: "15 sec")
        app.buttons["save-routine"].tap()
        let routine = app.buttons["routine-Evening reset"]
        XCTAssertTrue(routine.waitForExistence(timeout: 3))
        app.terminate()
        app.launchArguments = ["-ui-testing", "-preserve-routines"]
        app.launch()
        XCTAssertTrue(app.buttons["routine-Evening reset"].waitForExistence(timeout: 3))
        app.buttons["routine-Evening reset"].tap()
        XCTAssertTrue(app.staticTexts["Stretch"].exists)
        app.buttons["Routine options"].tap()
        app.buttons["Edit routine"].tap()
        app.textFields["routine-name"].tap()
        app.textFields["routine-name"].typeText(" plus")
        app.buttons["save-routine"].tap()
        XCTAssertTrue(app.staticTexts["Evening reset plus"].waitForExistence(timeout: 3))
        app.buttons["Routine options"].tap()
        app.buttons["Delete routine"].tap()
        app.buttons["Delete routine"].tap()
        XCTAssertTrue(app.buttons["create-routine"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["routine-Evening reset plus"].exists)
    }

    @MainActor
    func testNewStepsReuseExerciseAndRestDurationsIndependently() {
        let app = launch()
        app.buttons["create-routine"].tap()
        app.textFields["routine-name"].tap()
        app.textFields["routine-name"].typeText("My intervals\n")

        app.buttons["add-exercise"].tap()
        XCTAssertTrue(app.textFields["step-name"].waitForExistence(timeout: 4))
        app.textFields["step-name"].tap()
        app.textFields["step-name"].typeText("Squats")
        app.pickerWheels.element(boundBy: 0).adjust(toPickerWheelValue: "1 min")
        app.pickerWheels.element(boundBy: 1).adjust(toPickerWheelValue: "10 sec")
        app.buttons["save-step"].tap()
        addStep(app, name: nil, rest: true, seconds: "20 sec")

        app.buttons["add-exercise"].tap()
        XCTAssertTrue(app.textFields["step-name"].waitForExistence(timeout: 4))
        XCTAssertEqual(app.pickerWheels.element(boundBy: 0).value as? String, "1 min")
        XCTAssertEqual(app.pickerWheels.element(boundBy: 1).value as? String, "10 sec")
        capture(app, name: "remembered-exercise-duration")
        // An abandoned duration must not become the next default.
        app.pickerWheels.element(boundBy: 1).adjust(toPickerWheelValue: "40 sec")
        app.buttons["cancel-step"].tap()
        app.buttons["add-exercise"].tap()
        XCTAssertTrue(app.textFields["step-name"].waitForExistence(timeout: 4))
        XCTAssertEqual(app.pickerWheels.element(boundBy: 1).value as? String, "10 sec")
        app.textFields["step-name"].tap()
        app.textFields["step-name"].typeText("Plank")
        app.buttons["save-step"].tap()

        app.buttons["add-rest"].tap()
        XCTAssertTrue(app.textFields["step-name"].waitForExistence(timeout: 4))
        XCTAssertEqual(app.pickerWheels.element(boundBy: 0).value as? String, "0 min")
        XCTAssertEqual(app.pickerWheels.element(boundBy: 1).value as? String, "20 sec")
        capture(app, name: "remembered-rest-duration")
        app.buttons["save-step"].tap()
        app.buttons["save-routine"].tap()

        app.terminate()
        app.launchArguments = ["-ui-testing", "-preserve-routines"]
        app.launch()
        app.buttons["routine-My intervals"].tap()
        app.buttons["Routine options"].tap()
        app.buttons["Edit routine"].tap()
        // Existing routines seed defaults from their saved exercise and rest steps.
        app.swipeUp()
        app.buttons["add-exercise"].tap()
        XCTAssertTrue(app.textFields["step-name"].waitForExistence(timeout: 4))
        XCTAssertEqual(app.pickerWheels.element(boundBy: 0).value as? String, "1 min")
        XCTAssertEqual(app.pickerWheels.element(boundBy: 1).value as? String, "10 sec")
        app.buttons["cancel-step"].tap()
        app.buttons["add-rest"].tap()
        XCTAssertTrue(app.textFields["step-name"].waitForExistence(timeout: 4))
        XCTAssertEqual(app.pickerWheels.element(boundBy: 0).value as? String, "0 min")
        XCTAssertEqual(app.pickerWheels.element(boundBy: 1).value as? String, "20 sec")
    }

    @MainActor
    func testRoutineAndExerciseIconSelectionPersists() {
        let app = launch()
        app.buttons["create-routine"].tap()
        app.textFields["routine-name"].tap()
        app.textFields["routine-name"].typeText("Yoga flow\n")
        app.buttons["choose-routine-icon"].tap()
        XCTAssertTrue(app.buttons["icon-yoga"].waitForExistence(timeout: 3))
        capture(app, name: "icon-picker")
        app.buttons["icon-yoga"].tap()
        app.buttons["add-exercise"].tap()
        XCTAssertTrue(app.buttons["choose-exercise-icon"].waitForExistence(timeout: 3))
        app.buttons["choose-exercise-icon"].tap()
        app.buttons["icon-core"].tap()
        app.textFields["step-name"].tap()
        app.textFields["step-name"].typeText("Plank")
        app.buttons["save-step"].tap()
        app.buttons["save-routine"].tap()
        app.terminate()
        app.launchArguments = ["-ui-testing", "-preserve-routines"]
        app.launch()
        app.buttons["routine-Yoga flow"].tap()
        XCTAssertTrue(app.images["Yoga routine icon"].exists)
        XCTAssertTrue(app.images["Core exercise icon"].exists)
        capture(app, name: "custom-routine-icons")
        app.buttons["Routine options"].tap()
        app.buttons["Edit routine"].tap()
        app.buttons["choose-routine-icon"].tap()
        XCTAssertTrue(app.buttons["icon-yoga"].isSelected)
        app.buttons["icon-running"].tap()
        app.buttons["save-routine"].tap()
        XCTAssertTrue(app.images["Running routine icon"].exists)
    }

    @MainActor
    func testPreparationAndLandscapeWorkout() {
        let app = launch()
        app.buttons["routine-Everyday energy"].tap()
        let startedAt = Date()
        app.buttons["start-routine"].tap()
        XCTAssertTrue(app.staticTexts["preparation-countdown"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["current-step"].exists)
        XCTAssertGreaterThan(app.frame.width, app.frame.height)
        capture(app, name: "landscape-preparation")
        XCTAssertTrue(app.staticTexts["current-step"].waitForExistence(timeout: 10))
        XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(startedAt), 5.5)
        XCTAssertEqual(app.staticTexts["current-step"].label, "Jumping jacks")
        XCTAssertGreaterThan(app.frame.width, app.frame.height)
        capture(app, name: "landscape-exercise")
        XCUIDevice.shared.orientation = .portrait
        XCTAssertGreaterThan(app.frame.width, app.frame.height)
        app.buttons["pause-resume"].tap()
        app.buttons["skip-step"].tap()
        XCTAssertEqual(app.staticTexts["current-step"].label, "Catch your breath")
        capture(app, name: "landscape-rest")
        for _ in 0..<6 { app.buttons["skip-step"].tap() }
        XCTAssertTrue(app.staticTexts["You showed up."].waitForExistence(timeout: 3))
        capture(app, name: "landscape-completion")
        app.buttons["restart-workout"].tap()
        XCTAssertTrue(app.staticTexts["preparation-countdown"].waitForExistence(timeout: 3))
        app.buttons["pause-resume"].tap()
        XCTAssertTrue(app.buttons["Resume"].exists)
        app.buttons["Close workout"].tap()
        app.buttons["End workout"].tap()
        XCTAssertTrue(app.buttons["start-routine"].waitForExistence(timeout: 3))
        XCTAssertLessThan(app.frame.width, app.frame.height)
    }

    @MainActor
    func testPauseSkipRestCompleteAndRestart() {
        let app = launch()
        app.buttons["routine-Everyday energy"].tap()
        app.buttons["start-routine"].tap()
        XCTAssertTrue(app.staticTexts["current-step"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["current-step"].label, "Jumping jacks")
        XCTAssertFalse(app.staticTexts["Sound is unavailable. Visual cues and haptics are still on."].exists)
        app.buttons["pause-resume"].tap()
        let pausedTime = app.staticTexts["countdown"].label
        XCTAssertTrue(app.buttons["Resume"].exists)
        XCTAssertEqual(app.staticTexts["countdown"].label, pausedTime)
        app.buttons["skip-step"].tap()
        XCTAssertEqual(app.staticTexts["current-step"].label, "Catch your breath")
        XCTAssertEqual(app.staticTexts["countdown"].label, "00:15")
        app.buttons["pause-resume"].tap()
        app.buttons["Mute sounds"].tap()
        XCTAssertTrue(app.buttons["Unmute sounds"].exists)
        for _ in 0..<6 { app.buttons["skip-step"].tap() }
        XCTAssertTrue(app.staticTexts["You showed up."].waitForExistence(timeout: 3))
        app.buttons["restart-workout"].tap()
        XCTAssertTrue(app.staticTexts["preparation-countdown"].waitForExistence(timeout: 3))
        app.buttons["skip-preparation"].tap()
        XCTAssertEqual(app.staticTexts["current-step"].label, "Jumping jacks")
        app.buttons["Close workout"].tap()
        app.buttons["End workout"].tap()
        XCTAssertTrue(app.buttons["start-routine"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testShortRoutineAdvancesAndFinishesNaturally() {
        let app = launch()
        app.buttons["create-routine"].tap()
        app.textFields["routine-name"].tap()
        app.textFields["routine-name"].typeText("Quick check\n")
        addStep(app, name: "Move", rest: false, seconds: "3 sec")
        addStep(app, name: nil, rest: true, seconds: "3 sec")
        addStep(app, name: "Stretch", rest: false, seconds: "3 sec")
        app.buttons["save-routine"].tap()
        app.buttons["routine-Quick check"].tap()
        app.buttons["start-routine"].tap()
        let restAppears = NSPredicate(format: "label == %@", "Rest")
        expectation(for: restAppears, evaluatedWith: app.staticTexts["current-step"])
        waitForExpectations(timeout: 14)
        XCTAssertTrue(app.staticTexts["You showed up."].waitForExistence(timeout: 8))
        app.buttons["finish-workout"].tap()
        XCTAssertTrue(app.buttons["start-routine"].exists)
    }

    @MainActor
    func testBackgroundingPausesWorkout() {
        let app = launch()
        app.buttons["routine-Everyday energy"].tap()
        app.buttons["start-routine"].tap()
        XCTAssertTrue(app.buttons["pause-resume"].waitForExistence(timeout: 3))
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.buttons["Resume"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Paused when you left the app. Resume when you’re ready."].exists)
    }

    @MainActor
    private func addStep(_ app: XCUIApplication, name: String?, rest: Bool, seconds: String) {
        app.buttons[rest ? "add-rest" : "add-exercise"].tap()
        XCTAssertTrue(app.textFields["step-name"].waitForExistence(timeout: 4))
        if let name {
            app.textFields["step-name"].tap()
            app.textFields["step-name"].typeText(name)
        }
        app.pickerWheels.element(boundBy: 1).adjust(toPickerWheelValue: seconds)
        app.buttons["save-step"].tap()
    }
}
