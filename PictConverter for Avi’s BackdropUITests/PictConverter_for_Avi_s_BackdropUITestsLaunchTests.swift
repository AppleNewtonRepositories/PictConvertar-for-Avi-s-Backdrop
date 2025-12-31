//
//  PictConverter_for_Avi_s_BackdropUITestsLaunchTests.swift
//  PictConverter for Avi’s BackdropUITests
//
//  Created by Pawel Piotrowski on 21/12/2025.
//

import XCTest

final class PictConverter_for_Avi_s_BackdropUITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launch()

        // Insert steps here to perform after app launch but before taking a screenshot,
        // such as logging into a test account or navigating somewhere in the app

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
