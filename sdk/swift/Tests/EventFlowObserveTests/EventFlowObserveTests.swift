import XCTest
@testable import EventFlowObserve

final class EventFlowObserveTests: XCTestCase {
    override func setUp() {
        super.setUp()
        EventFlowObserve.shared.stop()
        EventFlowObserve.shared.clearCapturedRequests()
    }

    override func tearDown() {
        EventFlowObserve.shared.stop()
        super.tearDown()
    }

    func testDefaultConfiguration() {
        let config = EventFlowObserveConfig.default
        XCTAssertFalse(config.debugMode)
        XCTAssertTrue(config.allowedDomains.isEmpty)
        XCTAssertTrue(config.excludedDomains.isEmpty)
        XCTAssertTrue(config.captureRequestBody)
        XCTAssertEqual(config.samplingRate, 1.0)
        XCTAssertTrue(config.schemes.contains("http"))
        XCTAssertTrue(config.schemes.contains("https"))
    }

    func testDebugConfiguration() {
        let config = EventFlowObserveConfig.debug
        XCTAssertTrue(config.debugMode)
    }

    func testStartStop() {
        XCTAssertFalse(EventFlowObserve.shared.isActive)

        EventFlowObserve.shared.start()
        XCTAssertTrue(EventFlowObserve.shared.isActive)

        EventFlowObserve.shared.stop()
        XCTAssertFalse(EventFlowObserve.shared.isActive)
    }

    func testCapturedRequestModel() {
        let url = URL(string: "https://api.example.com/users")!
        let body = "{\"name\": \"test\"}".data(using: .utf8)

        let request = CapturedRequest(
            url: url,
            method: "POST",
            headers: ["Content-Type": "application/json"],
            body: body
        )

        XCTAssertEqual(request.host, "api.example.com")
        XCTAssertEqual(request.path, "/users")
        XCTAssertEqual(request.method, "POST")
        XCTAssertNotNil(request.bodyString)
        XCTAssertNotNil(request.bodyJSON)
    }

    func testSamplingRateClamping() {
        let config1 = EventFlowObserveConfig(samplingRate: 1.5)
        XCTAssertEqual(config1.samplingRate, 1.0)

        let config2 = EventFlowObserveConfig(samplingRate: -0.5)
        XCTAssertEqual(config2.samplingRate, 0.0)
    }

    func testHandlerRegistration() {
        let token = EventFlowObserve.shared.onRequestCaptured { _ in }
        XCTAssertNotNil(token)

        // Should not crash
        EventFlowObserve.shared.removeHandler(token: token)
    }
}
