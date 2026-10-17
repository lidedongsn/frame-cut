import FCCore
@testable import FCEngine
import XCTest

final class AdaptiveSettingsTests: XCTestCase {
    private func project(_ sizes: [(Int, Int)], hdr: HDRFormat? = nil, frameRate: Int = 30) -> Project {
        var p = Project(name: "t")
        for (w, h) in sizes {
            let a = MediaAsset(kind: .video, name: "v", path: "/v\(UUID())", duration: Time(seconds: 5), width: w, height: h,
                               hasAudio: true, frameRate: 30, hdr: hdr)
            p.addAssets([a])
            p.appendToMain(assetID: a.id)
        }
        p.setFrameRate(frameRate)
        return p
    }

    func testRecommendedExportMatchesSource() {
        let s = ExportSettings.recommended(for: project([(1920, 1080)], frameRate: 25))
        XCTAssertEqual(s.shortSide, 1080)
        XCTAssertEqual(s.frameRate, 25)
        XCTAssertEqual(s.codec, .h264)
        XCTAssertEqual(s.dynamicRange, .sdr)
    }

    func testRecommendedExport4KSource() {
        XCTAssertEqual(ExportSettings.recommended(for: project([(3840, 2160), (1920, 1080)])).shortSide, 2160)
        XCTAssertEqual(ExportSettings.recommended(for: project([(2160, 3840)])).shortSide, 2160)   // 竖拍 4K
    }

    func testRecommendedExportSmallSourceNotUpscaled() {
        XCTAssertEqual(ExportSettings.recommended(for: project([(1280, 720)])).shortSide, 720)
        XCTAssertEqual(ExportSettings.recommended(for: project([(640, 360)])).shortSide, 720)    // 最低 720p
        XCTAssertEqual(ExportSettings.recommended(for: project([(2560, 1440)])).shortSide, 1080) // 2K → 1080p
    }

    func testRecommendedExportHDR() {
        let s = ExportSettings.recommended(for: project([(3840, 2160)], hdr: .dolbyVision))
        XCTAssertEqual(s.dynamicRange, .hlg)
        XCTAssertEqual(s.effectiveCodec, .hevc)
    }

    func testPreviewTierFollowsViewSize() {
        XCTAssertEqual(PreviewQuality.shortSide(viewPixels: 300, cap: 1080), 360)
        XCTAssertEqual(PreviewQuality.shortSide(viewPixels: 500, cap: 1080), 540)
        XCTAssertEqual(PreviewQuality.shortSide(viewPixels: 1240, cap: 1080), 1080)   // Retina 大窗口
        XCTAssertEqual(PreviewQuality.shortSide(viewPixels: 1240, cap: 720), 720)     // 卡顿后降档的上限
    }

    func testPreviewStepsDownWhenRenderTooSlow() {
        // 30fps 每帧 33ms；渲染平均 30ms 超过 80% 预算 → 降一档
        XCTAssertEqual(PreviewQuality.capAfterMeasuring(cap: 1080, averageRenderMs: 30, frameRate: 30), 720)
        XCTAssertEqual(PreviewQuality.capAfterMeasuring(cap: 1080, averageRenderMs: 10, frameRate: 30), 1080)
        XCTAssertEqual(PreviewQuality.capAfterMeasuring(cap: 360, averageRenderMs: 50, frameRate: 30), 360)   // 已到最低
    }

    func testRenderTimerAverages() {
        let timer = RenderTimer()
        XCTAssertNil(timer.averageMs)
        timer.record(ms: 10)
        timer.record(ms: 20)
        XCTAssertEqual(timer.averageMs ?? 0, 15, accuracy: 0.01)
        timer.reset()
        XCTAssertNil(timer.averageMs)
    }
}
