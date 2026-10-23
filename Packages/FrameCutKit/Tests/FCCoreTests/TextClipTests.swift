@testable import FCCore
import XCTest

/// 文字与标题：独立于字幕的文字片段，各自有样式、位置和入场动画。
@MainActor
final class TextClipTests: XCTestCase {
    private func t(_ s: Double) -> Time { Time(seconds: s) }

    private func clip(_ start: Double, _ end: Double, _ text: String = "标题", animation: TextAnimation = .none) -> TextClip {
        TextClip(start: t(start), end: t(end), text: text, animation: animation)
    }

    // MARK: 编辑

    func testAddUpdateDuplicateRemove() {
        var p = Project(name: "x")
        let a = p.addText(clip(5, 8, "B"))
        let b = p.addText(clip(1, 3, "A"))
        XCTAssertEqual(p.texts.map(\.text), ["A", "B"], "按开始时间排序")

        p.updateText(id: a) { $0.start = t(-2); $0.end = t(-1) }
        XCTAssertEqual(p.text(id: a)?.start, .zero, "开始时间不早于 0")
        XCTAssertEqual(p.text(id: a)?.duration, EditLimits.minClipDuration, "时长不短于最小值")

        let copy = p.duplicateText(id: b)
        XCTAssertNotNil(copy)
        XCTAssertEqual(p.text(id: copy!)?.start, t(3), "副本接在原片段后面")
        XCTAssertEqual(p.text(id: copy!)?.text, "A")

        p.removeText(id: b)
        XCTAssertNil(p.text(id: b))
        XCTAssertEqual(p.texts.count, 2)
    }

    func testOldProjectsDecodeWithoutTexts() throws {
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Project(name: "x"))) as! [String: Any]
        json["texts"] = nil
        let p = try JSONDecoder().decode(Project.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(p.texts, [])
    }

    func testTextRoundTrip() throws {
        var p = Project(name: "x")
        var c = clip(1, 4, "Day 1", animation: .pop)
        c.style.fontName = "AvenirNext-Heavy"
        c.style.horizontalPosition = 0.2
        p.addText(c)
        let decoded = try JSONDecoder().decode(Project.self, from: JSONEncoder().encode(p))
        XCTAssertEqual(decoded.texts, p.texts)
    }

    // MARK: 时间线分行

    func testLanesPackOverlappingTexts() {
        let a = clip(0, 4), b = clip(2, 6), c = clip(4, 8), d = clip(3, 5)
        let lanes = TextClip.lanes([a, b, c, d])
        XCTAssertEqual(lanes[a.id], 0)
        XCTAssertEqual(lanes[b.id], 1)
        XCTAssertEqual(lanes[d.id], 2, "与 a、b 都重叠")
        XCTAssertEqual(lanes[c.id], 0, "a 结束后复用第一行")
        XCTAssertEqual(TextClip.laneCount([a, b, c, d]), 3)
        XCTAssertEqual(TextClip.laneCount([]), 0)
    }

    // MARK: 跟随主轨

    /// 三个片段各 10 秒，第二个片段上有一个地点标注。
    private func store() -> EditorStore {
        var p = makeProject(clipSeconds: [10, 10, 10])
        p.addText(clip(12, 15, "地点"))
        return EditorStore(project: p)
    }

    func testTextsFollowMainWhenEarlierClipDeleted() {
        let s = store()
        s.perform { $0.removeMain(id: $0.mainTrack[0].id) }
        XCTAssertEqual(s.project.texts.map(\.start), [t(2)])
        XCTAssertEqual(s.project.texts.map(\.end), [t(5)])
    }

    func testTextsFollowEvenWhenSubtitleFollowIsOff() {
        let s = store()
        s.perform { $0.subtitlesFollowMain = false }
        s.perform { $0.removeMain(id: $0.mainTrack[0].id) }
        XCTAssertEqual(s.project.texts.map(\.start), [t(2)])
    }

    func testTextsOfDeletedClipAreRemoved() {
        let s = store()
        s.perform { $0.removeMain(id: $0.mainTrack[1].id) }
        XCTAssertEqual(s.project.texts, [])
    }

    func testEditingTextDoesNotRemapIt() {
        let s = store()
        let id = s.project.texts[0].id
        s.perform { $0.updateText(id: id) { $0.start = Time(seconds: 20); $0.end = Time(seconds: 23) } }
        XCTAssertEqual(s.project.text(id: id)?.start, t(20))
    }

    func testDragTrimBackRestoresTexts() {
        let s = store()
        let first = s.project.mainTrack[0]
        s.beginCoalescing()
        s.perform { $0.trimMain(id: first.id, sourceIn: first.sourceIn, sourceOut: Time(seconds: 4)) }
        XCTAssertEqual(s.project.texts.map(\.start), [t(6)])
        s.perform { $0.trimMain(id: first.id, sourceIn: first.sourceIn, sourceOut: first.sourceOut) }
        s.endCoalescing()
        XCTAssertEqual(s.project.texts.map(\.start), [t(12)])
    }

    // MARK: 动画

    func testNoAnimationIsAlwaysFullyVisible() {
        let c = clip(0, 3)
        XCTAssertEqual(c.appearance(at: t(0)), TextAppearance())
        XCTAssertEqual(c.appearance(at: t(2.99)), TextAppearance())
    }

    func testFadeInAndOut() {
        let c = clip(0, 3, animation: .fade)
        XCTAssertEqual(c.appearance(at: t(0)).opacity, 0, accuracy: 0.001)
        XCTAssertEqual(c.appearance(at: t(1.5)).opacity, 1, accuracy: 0.001)
        XCTAssertLessThan(c.appearance(at: t(2.97)).opacity, 0.5)
        XCTAssertGreaterThan(c.appearance(at: t(0.2)).opacity, 0)
    }

    func testAnimationShortensForShortClips() {
        let c = clip(0, 0.3, animation: .fade)
        XCTAssertEqual(c.appearance(at: t(0.15)).opacity, 1, accuracy: 0.001, "短片段中间完全可见")
    }

    func testRiseStartsBelowAndSettles() {
        let c = clip(0, 3, animation: .rise)
        XCTAssertGreaterThan(c.appearance(at: t(0.05)).offsetY, 0)
        XCTAssertEqual(c.appearance(at: t(1)).offsetY, 0, accuracy: 0.0001)
    }

    func testPopScalesUpToFullSize() {
        let c = clip(0, 3, animation: .pop)
        XCTAssertLessThan(c.appearance(at: t(0.02)).scale, 0.8)
        XCTAssertEqual(c.appearance(at: t(1)).scale, 1, accuracy: 0.0001)
    }

    func testTypewriterRevealsCharactersProgressively() {
        let c = clip(0, 4, "你好世界", animation: .typewriter)
        XCTAssertEqual(c.appearance(at: t(0)).visibleCharacters, 0)
        let mid = c.appearance(at: t(0.2)).visibleCharacters ?? 0
        XCTAssertTrue((1...3).contains(mid), "中途显示一部分，实际 \(mid)")
        XCTAssertEqual(c.appearance(at: t(3)).visibleCharacters, 4)
    }
}
