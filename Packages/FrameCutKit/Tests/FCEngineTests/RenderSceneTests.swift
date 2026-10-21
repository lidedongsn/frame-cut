import FCCore
@testable import FCEngine
import XCTest

final class RenderSceneTests: XCTestCase {
    /// 字幕时间重叠时两条都显示，按开始时间从上到下排开，不叠在一起。
    func testOverlappingSubtitlesStackVertically() {
        let a = Subtitle(start: Time(seconds: 0), end: Time(seconds: 3), text: "第一条")
        let b = Subtitle(start: Time(seconds: 2), end: Time(seconds: 4), text: "第二条")
        let scene = RenderScene(subtitles: [b, a], style: SubtitleStyle())
        XCTAssertEqual(scene.activeSubtitles(at: Time(seconds: 1)).map(\.text), ["第一条"])
        XCTAssertEqual(scene.activeSubtitles(at: Time(seconds: 2.5)).map(\.text), ["第一条", "第二条"])

        let canvas = CGSize(width: 640, height: 360)
        let lines = SubtitleRenderer.layout(scene.activeSubtitles(at: Time(seconds: 2.5)), style: scene.style, canvas: canvas)
        XCTAssertEqual(lines.count, 2)
        XCTAssertLessThanOrEqual(lines[0].rect.maxY, lines[1].rect.minY, "第一条在上，不重叠")
        XCTAssertTrue(lines.allSatisfy { CGRect(origin: .zero, size: canvas).contains($0.rect) })
    }

    /// 拖动位置时位图不变，不应该产生新的缓存条目。
    func testPositionDoesNotAffectRenderCache() {
        SubtitleRenderer.purge()
        var style = SubtitleStyle()
        let canvas = CGSize(width: 640, height: 360)
        _ = SubtitleRenderer.image(text: "缓存", style: style, canvas: canvas)
        style.horizontalPosition = 0.2
        style.verticalPosition = 0.3
        _ = SubtitleRenderer.image(text: "缓存", style: style, canvas: canvas)
        XCTAssertEqual(SubtitleRenderer.cachedCount, 1)
    }
}
