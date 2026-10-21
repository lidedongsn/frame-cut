@testable import FCCore
import XCTest

/// 字幕跟随主轨：删除 / 修剪 / 变速 / 调序片段后，字幕跟着它下面的画面走。
@MainActor
final class SubtitleFollowTests: XCTestCase {
    private func t(_ s: Double) -> Time { Time(seconds: s) }

    /// 三个片段各 10 秒，每个片段中间一条字幕。
    private func store() -> EditorStore {
        var p = makeProject(clipSeconds: [10, 10, 10])
        p.replaceSubtitles([Subtitle(start: t(2), end: t(4), text: "A"),
                            Subtitle(start: t(12), end: t(14), text: "B"),
                            Subtitle(start: t(22), end: t(24), text: "C")])
        return EditorStore(project: p)
    }

    private func times(_ s: EditorStore) -> [String] {
        s.project.subtitles.map { "\($0.text)\(String(format: "%g", $0.start.seconds))-\(String(format: "%g", $0.end.seconds))" }
    }

    func testDeletingClipRemovesItsSubtitlesAndShiftsLater() {
        let s = store()
        s.perform { $0.removeMain(id: $0.mainTrack[0].id) }
        XCTAssertEqual(times(s), ["B2-4", "C12-14"])
    }

    func testTrimmingClipStartShiftsSubtitles() {
        let s = store()
        s.perform { p in let c = p.mainTrack[1]; p.trimMain(id: c.id, sourceIn: t(5), sourceOut: c.sourceOut) }
        // B（源 2–4 秒）整条被剪掉 → 删除；C 前移 5 秒
        XCTAssertEqual(times(s), ["A2-4", "C17-19"])
    }

    func testPartiallyTrimmedSubtitleIsClipped() {
        let s = store()
        s.perform { p in let c = p.mainTrack[0]; p.trimMain(id: c.id, sourceIn: t(3), sourceOut: c.sourceOut) }
        XCTAssertEqual(times(s), ["A0-1", "B9-11", "C19-21"])
    }

    func testSpeedChangeScalesSubtitlesInClip() {
        let s = store()
        s.perform { $0.setSpeed(id: $0.mainTrack[0].id, 2) }
        XCTAssertEqual(times(s), ["A1-2", "B7-9", "C17-19"])
    }

    func testReorderMovesSubtitlesWithClip() {
        let s = store()
        s.perform { $0.moveMain(id: $0.mainTrack[2].id, to: 0) }
        XCTAssertEqual(times(s), ["C2-4", "A12-14", "B22-24"])
    }

    func testSplitDoesNotMoveSubtitles() {
        let s = store()
        s.perform { _ = $0.splitMain(at: t(13)) }
        XCTAssertEqual(times(s), ["A2-4", "B12-14", "C22-24"])
    }

    func testDragTrimBackRestoresSubtitles() {
        let s = store()
        let c = s.project.mainTrack[0]
        s.beginCoalescing()
        s.perform { $0.trimMain(id: c.id, sourceIn: t(5), sourceOut: c.sourceOut) }
        s.perform { $0.trimMain(id: c.id, sourceIn: t(1), sourceOut: c.sourceOut) }
        s.endCoalescing()
        XCTAssertEqual(times(s), ["A1-3", "B11-13", "C21-23"])
    }

    func testAddingTransitionShiftsLaterSubtitles() {
        let s = store()
        s.perform { $0.setTransition(Transition(kind: .dissolve, duration: Time(seconds: 1)), before: $0.mainTrack[1].id) }
        XCTAssertEqual(times(s), ["A2-4", "B11-13", "C21-23"])
    }

    func testUndoRestoresSubtitles() {
        let s = store()
        s.perform { $0.removeMain(id: $0.mainTrack[0].id) }
        s.undo()
        XCTAssertEqual(times(s), ["A2-4", "B12-14", "C22-24"])
    }

    func testFirstClipIntoEmptyTimelineKeepsSubtitles() {
        var p = makeProject(clipSeconds: [10])
        let asset = p.mainTrack[0].assetID
        p.mainTrack = []
        p.replaceSubtitles([Subtitle(start: t(2), end: t(4), text: "A")])
        let s = EditorStore(project: p)
        s.perform { _ = $0.appendToMain(assetID: asset) }
        XCTAssertEqual(times(s), ["A2-4"])
    }

    func testSubtitlesReplacedMidDragAreKept() {
        let s = store()
        let c = s.project.mainTrack[0]
        s.beginCoalescing()
        s.perform { $0.trimMain(id: c.id, sourceIn: t(1), sourceOut: c.sourceOut) }
        // 拖动中识别完成，整体替换字幕（按当前时间线）
        s.perform { $0.replaceSubtitles([Subtitle(start: t(20), end: t(21), text: "新")]) }
        s.perform { $0.trimMain(id: c.id, sourceIn: t(2), sourceOut: c.sourceOut) }
        s.endCoalescing()
        XCTAssertEqual(times(s), ["新19-20"])
    }

    /// 识别期间剪掉了开头：原声识别的字幕要换算到现在的时间线，不管跟随开关是否打开。
    func testTranscriptionMapsToEditedTimelineEvenWhenFollowOff() {
        var base = makeProject(clipSeconds: [10, 10])
        base.subtitlesFollowMain = false
        base.subtitlesFollowIsAutomatic = false
        var now = base
        now.removeMain(id: now.mainTrack[0].id)
        now.applyTranscription([Subtitle(start: t(12), end: t(14), text: "B")], recordedOn: base, original: true, music: false)
        XCTAssertEqual(now.subtitles.map { [$0.start, $0.end] }, [[t(2), t(4)]])
        XCTAssertFalse(now.subtitlesFollowMain, "用户手动关掉的跟随不能被识别改回去")
    }

    func testTranscriptionSetsFollowAutomatically() {
        var p = makeProject(clipSeconds: [10])
        p.applyTranscription([], recordedOn: p, original: false, music: true)
        XCTAssertFalse(p.subtitlesFollowMain, "只来自音频轨的字幕不跟随视频")
        p.applyTranscription([], recordedOn: p, original: true, music: false)
        XCTAssertTrue(p.subtitlesFollowMain)
        p.applyTranscription([], recordedOn: p, original: true, music: true)
        XCTAssertTrue(p.subtitlesFollowMain, "两者都有时保持不变")
    }

    func testOldProjectsDecodeFollowAsAutomatic() throws {
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Project(name: "x"))) as! [String: Any]
        json["subtitlesFollowIsAutomatic"] = nil
        let p = try JSONDecoder().decode(Project.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertTrue(p.subtitlesFollowIsAutomatic)
    }

    func testFollowDisabledLeavesSubtitles() {
        let s = store()
        s.perform { $0.subtitlesFollowMain = false }
        s.perform { $0.removeMain(id: $0.mainTrack[0].id) }
        XCTAssertEqual(times(s), ["A2-4", "B12-14", "C22-24"])
    }

    func testSubtitlesAfterTimelineEndShiftWithEnd() {
        let s = store()
        s.perform { $0.subtitles.append(Subtitle(start: t(31), end: t(32), text: "D")) }
        s.perform { $0.removeMain(id: $0.mainTrack[1].id) }
        XCTAssertEqual(times(s), ["A2-4", "C12-14", "D21-22"])
    }

    func testOldProjectsDecodeWithFollowEnabled() throws {
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Project(name: "x"))) as! [String: Any]
        json["subtitlesFollowMain"] = nil
        let p = try JSONDecoder().decode(Project.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertTrue(p.subtitlesFollowMain)
    }
}
