import XCTest
@testable import FCCore

final class TimelineZoomTests: XCTestCase {
    func testAnchorStaysAtSameScreenPosition() {
        // 锚点 10s，旧缩放 60 点/秒，滚动原点 300：锚点屏幕位置 = 16 + 600 - 300 = 316
        let origin = TimelineZoom.scrollOrigin(anchor: Time(seconds: 10), oldPointsPerSecond: 60, newPointsPerSecond: 120,
                                               oldOrigin: 300, leading: 16)
        XCTAssertEqual(16 + 10 * 120 - origin, 316, accuracy: 0.001)
    }

    func testOriginNeverNegative() {
        let origin = TimelineZoom.scrollOrigin(anchor: Time(seconds: 1), oldPointsPerSecond: 60, newPointsPerSecond: 10,
                                               oldOrigin: 0, leading: 16)
        XCTAssertEqual(origin, 0)
    }

    func testClampedZoom() {
        XCTAssertEqual(TimelineZoom.clamped(1000), TimelineZoom.maxPointsPerSecond)
        XCTAssertEqual(TimelineZoom.clamped(1), TimelineZoom.minPointsPerSecond)
        XCTAssertEqual(TimelineZoom.clamped(60), 60)
    }

    func testScrollWheelFactor() {
        XCTAssertGreaterThan(TimelineZoom.factor(scrollDelta: 5), 1)   // 向上滚放大
        XCTAssertLessThan(TimelineZoom.factor(scrollDelta: -5), 1)
        XCTAssertEqual(TimelineZoom.factor(scrollDelta: 0), 1)
        // 对称：放大再缩小回到原值
        XCTAssertEqual(TimelineZoom.factor(scrollDelta: 3) * TimelineZoom.factor(scrollDelta: -3), 1, accuracy: 1e-9)
    }
}
