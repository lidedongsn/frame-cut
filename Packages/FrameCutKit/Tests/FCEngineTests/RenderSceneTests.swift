import FCCore
@testable import FCEngine
import XCTest

final class RenderSceneTests: XCTestCase {
    /// 字幕时间重叠时只显示后开始的那条，不叠在一起。
    func testOverlappingSubtitlesShowOnlyLatest() {
        let a = Subtitle(start: Time(seconds: 0), end: Time(seconds: 3), text: "A")
        let b = Subtitle(start: Time(seconds: 2), end: Time(seconds: 4), text: "B")
        let scene = RenderScene(subtitles: [a, b], style: SubtitleStyle())
        XCTAssertEqual(scene.activeSubtitle(at: Time(seconds: 1))?.text, "A")
        XCTAssertEqual(scene.activeSubtitle(at: Time(seconds: 2.5))?.text, "B")
        XCTAssertEqual(scene.activeSubtitle(at: Time(seconds: 3.5))?.text, "B")
        XCTAssertNil(scene.activeSubtitle(at: Time(seconds: 5)))
    }
}
