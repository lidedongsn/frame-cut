@testable import FCCore
import XCTest

/// 分离音频：把主轨视频的原声拆到音频轨上单独编辑，原片段静音。
@MainActor
final class DetachAudioTests: XCTestCase {
    private func t(_ s: Double) -> Time { Time(seconds: s) }

    func testDetachPlacesAudioUnderClipAndMutesIt() {
        var p = makeProject(clipSeconds: [4, 6])
        p.updateMain(id: p.mainTrack[1].id) { $0.sourceIn = Time(seconds: 10); $0.sourceOut = Time(seconds: 16); $0.volume = 0.7 }
        let clip = p.mainTrack[1]
        let id = p.detachAudio(id: clip.id)!
        let audio = p.music(id: id)!
        XCTAssertEqual(audio.assetID, clip.assetID)
        XCTAssertEqual(audio.start, t(4), "对齐到片段在时间线上的位置")
        XCTAssertEqual(audio.sourceIn, t(10))
        XCTAssertEqual(audio.sourceOut, t(16))
        XCTAssertEqual(audio.volume, 0.7, accuracy: 0.001, "带上原片段的音量")
        XCTAssertTrue(p.mainClip(id: clip.id)!.muted)
    }

    func testDetachKeepsTransitionFades() {
        var p = makeProject(clipSeconds: [4, 6, 4])
        p.setTransition(Transition(kind: .dissolve, duration: t(1)), before: p.mainTrack[1].id)
        p.setTransition(Transition(kind: .dissolve, duration: t(0.5)), before: p.mainTrack[2].id)
        let id = p.detachAudio(id: p.mainTrack[1].id)!
        let audio = p.music(id: id)!
        XCTAssertEqual(audio.start, t(3), "转场重叠后片段从 3 秒开始")
        XCTAssertEqual(audio.fadeIn, t(1), "原声在转场里是渐入的，分离后保持")
        XCTAssertEqual(audio.fadeOut, t(0.5))
    }

    func testCannotDetachWithoutAudioOrWhenSpeedChanged() {
        var p = makeProject(clipSeconds: [4, 4])
        let silent = MediaAsset(kind: .video, name: "s", path: "/s.mp4", duration: t(10), width: 1, height: 1, hasAudio: false, frameRate: 30)
        p.assets.append(silent)
        let silentClip = p.appendToMain(assetID: silent.id)!
        let image = MediaAsset(kind: .image, name: "i", path: "/i.jpg", duration: .zero, width: 1, height: 1, hasAudio: false, frameRate: 0)
        p.assets.append(image)
        let imageClip = p.appendToMain(assetID: image.id)!
        p.setSpeed(id: p.mainTrack[1].id, 2)

        XCTAssertTrue(p.canDetachAudio(id: p.mainTrack[0].id))
        XCTAssertFalse(p.canDetachAudio(id: silentClip))
        XCTAssertFalse(p.canDetachAudio(id: imageClip))
        XCTAssertFalse(p.canDetachAudio(id: p.mainTrack[1].id), "变速片段的声音无法原样放到音频轨")
        XCTAssertNil(p.detachAudio(id: p.mainTrack[1].id))
        XCTAssertFalse(p.mainTrack[1].muted)
        XCTAssertEqual(p.musicTrack, [])
    }

    /// 已静音（包括已经分离过）的片段不能再分离：否则会叠出一份同样的声音，或让本来静音的原声响起来。
    func testCannotDetachMutedClip() {
        var p = makeProject(clipSeconds: [5])
        let id = p.mainTrack[0].id
        XCTAssertNotNil(p.detachAudio(id: id))
        XCTAssertFalse(p.canDetachAudio(id: id))
        XCTAssertNil(p.detachAudio(id: id))
        XCTAssertEqual(p.musicTrack.count, 1)
    }

    /// 音频轨上来自视频文件的声音（分离出的原声）算「视频原声」，配乐、旁白不算。
    func testOriginalSoundIncludesDetachedAudio() {
        var p = makeProject(clipSeconds: [5])
        let bgm = MediaAsset(kind: .audio, name: "bgm", path: "/bgm", duration: t(30), width: 0, height: 0, hasAudio: true, frameRate: 0)
        p.assets.append(bgm)
        let music = p.addMusic(assetID: bgm.id, at: .zero)!
        let detached = p.detachAudio(id: p.mainTrack[0].id)!
        XCTAssertTrue(p.isOriginalSound(p.music(id: detached)!))
        XCTAssertFalse(p.isOriginalSound(p.music(id: music)!))
    }

    func testDetachedAudioGoesToFreeLane() {
        var p = makeProject(clipSeconds: [10])
        let bgm = MediaAsset(kind: .audio, name: "bgm", path: "/bgm", duration: t(30), width: 0, height: 0, hasAudio: true, frameRate: 0)
        p.assets.append(bgm)
        p.addMusic(assetID: bgm.id, at: .zero)
        let id = p.detachAudio(id: p.mainTrack[0].id)!
        XCTAssertEqual(p.music(id: id)?.lane, 1, "和配乐重叠，放到第二条轨")
    }

    func testUndoRestoresClipAudio() {
        let s = EditorStore(project: makeProject(clipSeconds: [5]))
        let clipID = s.project.mainTrack[0].id
        s.perform { _ = $0.detachAudio(id: clipID) }
        XCTAssertEqual(s.project.musicTrack.count, 1)
        s.undo()
        XCTAssertEqual(s.project.musicTrack, [])
        XCTAssertFalse(s.project.mainTrack[0].muted)
    }
}
