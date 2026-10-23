import FCCore
@testable import FCEngine
import CoreImage
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

    // MARK: 文字

    func testActiveTextsSortedByStart() {
        let a = TextClip(start: Time(seconds: 0), end: Time(seconds: 3), text: "A")
        let b = TextClip(start: Time(seconds: 1), end: Time(seconds: 2), text: "B")
        let scene = RenderScene(subtitles: [], style: SubtitleStyle(), texts: [b, a])
        XCTAssertEqual(scene.activeTexts(at: Time(seconds: 1.5)).map(\.text), ["A", "B"], "后开始的画在上面")
        XCTAssertEqual(scene.activeTexts(at: Time(seconds: 2.5)).map(\.text), ["A"])
    }

    /// 文字按自己的样式定位；不可见时不渲染。
    func testTextPlacedAtItsOwnPosition() throws {
        let canvas = CGSize(width: 640, height: 360)
        var clip = TextClip(start: .zero, end: Time(seconds: 3), text: "地点", animation: .none)
        clip.style.horizontalPosition = 0.25
        clip.style.verticalPosition = 0.2
        let placed = try XCTUnwrap(TextRenderer.render(clip, at: Time(seconds: 1), canvas: canvas))
        // Core Image 原点在左下：顶部 20% 处 → y 中心约 288
        XCTAssertEqual(placed.extent.midX, 160, accuracy: 2)
        XCTAssertEqual(placed.extent.midY, 288, accuracy: 2)

        clip.animation = .fade
        XCTAssertNil(TextRenderer.render(clip, at: .zero, canvas: canvas), "淡入开始时完全透明")
    }

    /// 打字机效果：未打出的字透明，但版面与完整文字一致，不会边打边挪。
    func testTypewriterKeepsLayoutStable() throws {
        let canvas = CGSize(width: 640, height: 360)
        let clip = TextClip(start: .zero, end: Time(seconds: 4), text: "你好世界", animation: .typewriter)
        let partial = try XCTUnwrap(TextRenderer.render(clip, at: Time(seconds: 0.15), canvas: canvas))
        let full = try XCTUnwrap(TextRenderer.render(clip, at: Time(seconds: 3), canvas: canvas))
        XCTAssertEqual(partial.extent, full.extent)
        let partialImage = try XCTUnwrap(SubtitleRenderer.image(text: clip.text, style: clip.style, canvas: canvas, visibleCharacters: 2))
        let fullImage = try XCTUnwrap(SubtitleRenderer.image(text: clip.text, style: clip.style, canvas: canvas))
        XCTAssertLessThan(alphaSum(partialImage), alphaSum(fullImage) * 0.8, "只画出一部分字")
    }

    private func alphaSum(_ image: CIImage) -> Double {
        let context = CIContext()
        let w = Int(image.extent.width), h = Int(image.extent.height)
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        context.render(image, toBitmap: &pixels, rowBytes: w * 4, bounds: image.extent, format: .RGBA8, colorSpace: nil)
        return stride(from: 3, to: pixels.count, by: 4).reduce(0) { $0 + Double(pixels[$1]) }
    }
}
