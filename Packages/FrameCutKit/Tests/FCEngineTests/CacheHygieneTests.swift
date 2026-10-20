import CoreImage
import FCCore
@testable import FCEngine
@testable import FCMedia
import XCTest

/// 缓存都有上限，关闭工程时可以整体释放。
final class CacheHygieneTests: XCTestCase {
    func testThumbnailGeneratorsBoundedAndPurgeable() async throws {
        let provider = ThumbnailProvider()
        let url = try TestMedia.url("landscape_10s.mp4")
        // 不存在的路径同样会创建生成器，用来模拟很多素材
        for i in 0..<(ThumbnailProvider.generatorLimit + 10) {
            _ = await provider.thumbnail(url: URL(fileURLWithPath: "/nonexistent/\(i).mov"), time: .zero, maxHeight: 60)
        }
        let count = await provider.generatorCount
        XCTAssertLessThanOrEqual(count, ThumbnailProvider.generatorLimit)
        _ = await provider.thumbnail(url: url, time: Time(seconds: 1), maxHeight: 60)
        await provider.purge()
        let after = await provider.generatorCount
        XCTAssertEqual(after, 0)
    }

    func testWaveformCacheBoundedAndPurgeable() async throws {
        let provider = WaveformProvider()
        let url = try TestMedia.url("tone_20s.m4a")
        for perSecond in 1...(WaveformProvider.cacheLimit + 5) {
            _ = await provider.peaks(url: url, perSecond: perSecond)
        }
        let count = await provider.cachedCount
        XCTAssertLessThanOrEqual(count, WaveformProvider.cacheLimit)
        await provider.purge()
        let after = await provider.cachedCount
        XCTAssertEqual(after, 0)
    }

    func testStillImageCacheHasByteLimit() {
        XCTAssertLessThanOrEqual(FrameRenderer.stillImageByteLimit, 512 * 1024 * 1024)
        XCTAssertGreaterThan(FrameRenderer.stillImageByteLimit, 0)
    }

    func testPurgeRenderCaches() {
        let f = FilterSettings(preset: .warm)
        _ = FilterLUT.data(f, space: .sdr)
        XCTAssertTrue(FilterLUT.isCached(f, space: .sdr))
        _ = SubtitleRenderer.image(text: "缓存", style: SubtitleStyle(), canvas: CGSize(width: 640, height: 360))
        RenderCaches.purge()
        XCTAssertFalse(FilterLUT.isCached(f, space: .sdr))
        XCTAssertEqual(SubtitleRenderer.cachedCount, 0)
    }
}
