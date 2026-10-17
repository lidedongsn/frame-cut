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
        XCTAssertEqual(TimelineZoom.clamped(100_000), TimelineZoom.maxPointsPerSecond)
        XCTAssertEqual(TimelineZoom.clamped(0.01), TimelineZoom.minPointsPerSecond)
        XCTAssertEqual(TimelineZoom.clamped(60), 60)
    }

    /// 缩到最小时，20 分钟的视频能放进约 1200pt 宽的时间线。
    func testZoomOutFitsLongVideo() {
        XCTAssertLessThanOrEqual(TimelineZoom.minPointsPerSecond * 20 * 60, 1200)
    }

    /// 放到最大时，30fps 下每帧至少 30pt，可以逐帧对齐。
    func testZoomInReachesFrameLevel() {
        XCTAssertGreaterThanOrEqual(TimelineZoom.maxPointsPerSecond / 30, 30)
    }

    /// 适应窗口：整段时长恰好铺满可视宽度（减去左右留白）。
    func testFitToWidth() {
        let pps = TimelineZoom.fit(duration: Time(seconds: 180), viewportWidth: 1016, leading: 16, trailing: 100)
        XCTAssertEqual(pps, 5, accuracy: 0.001)
        XCTAssertEqual(TimelineZoom.fit(duration: .zero, viewportWidth: 1000, leading: 16, trailing: 100), 60)
    }

    func testScrollWheelFactor() {
        XCTAssertGreaterThan(TimelineZoom.factor(scrollDelta: 5), 1)   // 向上滚放大
        XCTAssertLessThan(TimelineZoom.factor(scrollDelta: -5), 1)
        XCTAssertEqual(TimelineZoom.factor(scrollDelta: 0), 1)
        // 对称：放大再缩小回到原值
        XCTAssertEqual(TimelineZoom.factor(scrollDelta: 3) * TimelineZoom.factor(scrollDelta: -3), 1, accuracy: 1e-9)
    }
}
