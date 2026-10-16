import XCTest
@testable import FCCore

final class ProjectEditingTests: XCTestCase {
    func testAppendVideoAndImage() {
        var p = Project(name: "t")
        let v = MediaAsset(kind: .video, name: "v", path: "/v", duration: Time(seconds: 8), width: 1, height: 1, hasAudio: true, frameRate: 30)
        let i = MediaAsset(kind: .image, name: "i", path: "/i", duration: .zero, width: 1, height: 1, hasAudio: false, frameRate: 0)
        let a = MediaAsset(kind: .audio, name: "a", path: "/a", duration: Time(seconds: 8), width: 0, height: 0, hasAudio: true, frameRate: 0)
        p.assets = [v, i, a]
        XCTAssertNotNil(p.appendToMain(assetID: v.id))
        XCTAssertNotNil(p.appendToMain(assetID: i.id))
        XCTAssertNil(p.appendToMain(assetID: a.id))
        XCTAssertEqual(p.mainTrack.map(\.sourceDuration), [Time(seconds: 8), Time(seconds: 3)])
    }

    func testSplitInMiddle() {
        var p = makeProject(clipSeconds: [10])
        let originalID = p.mainTrack[0].id
        let newID = p.splitMain(at: Time(seconds: 4))
        XCTAssertNotNil(newID)
        XCTAssertEqual(p.mainTrack.count, 2)
        XCTAssertEqual(p.mainTrack[0].id, originalID)
        XCTAssertEqual(p.mainTrack[0].sourceIn, .zero)
        XCTAssertEqual(p.mainTrack[0].sourceOut, Time(seconds: 4))
        XCTAssertEqual(p.mainTrack[1].id, newID)
        XCTAssertEqual(p.mainTrack[1].sourceIn, Time(seconds: 4))
        XCTAssertEqual(p.mainTrack[1].sourceOut, Time(seconds: 10))
    }

    func testSplitRespectsSpeed() {
        var p = makeProject(clipSeconds: [10])
        p.mainTrack[0].speed = 2
        _ = p.splitMain(at: Time(seconds: 2))
        XCTAssertEqual(p.mainTrack[0].sourceOut, Time(seconds: 4))
        XCTAssertEqual(p.mainTrack[1].speed, 2)
    }

    func testSplitKeepsIncomingTransitionOnFirstHalf() {
        var p = makeProject(clipSeconds: [4, 4])
        p.transitions[p.mainTrack[1].id] = Transition(kind: .dissolve, duration: Time(seconds: 1))
        _ = p.splitMain(at: Time(seconds: 5))
        XCTAssertEqual(p.mainTrack.count, 3)
        XCTAssertNotNil(p.transitions[p.mainTrack[1].id])
        XCTAssertNil(p.transitions[p.mainTrack[2].id])
    }

    func testSplitNearEdgeRejected() {
        var p = makeProject(clipSeconds: [10])
        XCTAssertNil(p.splitMain(at: Time(seconds: 0.05)))
        XCTAssertNil(p.splitMain(at: Time(seconds: 9.95)))
        XCTAssertEqual(p.mainTrack.count, 1)
    }

    func testRemoveDropsTransition() {
        var p = makeProject(clipSeconds: [3, 3])
        let id = p.mainTrack[1].id
        p.transitions[id] = Transition(kind: .dissolve)
        p.removeMain(id: id)
        XCTAssertEqual(p.mainTrack.count, 1)
        XCTAssertTrue(p.transitions.isEmpty)
    }

    func testMove() {
        var p = makeProject(clipSeconds: [1, 2, 3])
        let id = p.mainTrack[0].id
        p.moveMain(id: id, to: 2)
        XCTAssertEqual(p.mainTrack.map(\.sourceOut.seconds), [2, 3, 1])
        p.moveMain(id: id, to: 0)
        XCTAssertEqual(p.mainTrack.map(\.sourceOut.seconds), [1, 2, 3])
    }

    func testTrimClamps() {
        var p = makeProject(clipSeconds: [10])
        let id = p.mainTrack[0].id
        p.trimMain(id: id, sourceIn: Time(seconds: -1), sourceOut: Time(seconds: 200))
        XCTAssertEqual(p.mainTrack[0].sourceIn, .zero)
        XCTAssertEqual(p.mainTrack[0].sourceOut, Time(seconds: 100)) // 资产时长 100s
        p.trimMain(id: id, sourceIn: Time(seconds: 5), sourceOut: Time(seconds: 5))
        XCTAssertEqual(p.mainTrack[0].sourceDuration, Time(seconds: 0.1))
    }

    func testSetSpeedClamps() {
        var p = makeProject(clipSeconds: [10])
        let id = p.mainTrack[0].id
        p.setSpeed(id: id, 10)
        XCTAssertEqual(p.mainTrack[0].speed, 4)
        p.setSpeed(id: id, 0.01)
        XCTAssertEqual(p.mainTrack[0].speed, 0.25)
    }

    func testApplyTransitionToAllSkipsFirst() {
        var p = makeProject(clipSeconds: [2, 2, 2])
        p.applyTransitionToAll(Transition(kind: .blur))
        XCTAssertNil(p.transitions[p.mainTrack[0].id])
        XCTAssertEqual(p.transitions.count, 2)
        p.applyTransitionToAll(nil)
        XCTAssertTrue(p.transitions.isEmpty)
    }

    func testApplyFilterToAll() {
        var p = makeProject(clipSeconds: [2, 2])
        p.applyFilterToAll(FilterSettings(preset: .film))
        XCTAssertEqual(p.mainTrack.map(\.filter.preset), [.film, .film])
    }

    func testMusicAddSplitRemove() {
        var p = makeProject(clipSeconds: [10])
        let a = MediaAsset(kind: .audio, name: "m", path: "/m", duration: Time(seconds: 20), width: 0, height: 0, hasAudio: true, frameRate: 0)
        p.assets.append(a)
        let id = p.addMusic(assetID: a.id, at: Time(seconds: 1))!
        XCTAssertEqual(p.musicTrack[0].end, Time(seconds: 21))
        let second = p.splitMusic(id: id, at: Time(seconds: 6))!
        XCTAssertEqual(p.musicTrack.count, 2)
        XCTAssertEqual(p.music(id: id)?.sourceOut, Time(seconds: 5))
        XCTAssertEqual(p.music(id: second)?.start, Time(seconds: 6))
        XCTAssertEqual(p.music(id: second)?.sourceIn, Time(seconds: 5))
        p.removeMusic(id: id)
        XCTAssertEqual(p.musicTrack.count, 1)
    }

    func testSubtitlesSorted() {
        var p = Project(name: "t")
        p.replaceSubtitles([Subtitle(start: Time(seconds: 5), end: Time(seconds: 6), text: "b"),
                            Subtitle(start: Time(seconds: 1), end: Time(seconds: 2), text: "a")])
        XCTAssertEqual(p.subtitles.map(\.text), ["a", "b"])
        let id = p.addSubtitle(at: Time(seconds: 3), text: "c")
        XCTAssertEqual(p.subtitles.map(\.text), ["a", "c", "b"])
        XCTAssertEqual(p.subtitle(id: id)?.end, Time(seconds: 5))
        p.removeSubtitle(id: id)
        XCTAssertEqual(p.subtitles.count, 2)
    }

    func testMissingAssets() {
        let p = makeProject(clipSeconds: [1])
        XCTAssertEqual(p.missingAssets(fileExists: { _ in false }).count, 1)
        XCTAssertEqual(p.missingAssets(fileExists: { _ in true }).count, 0)
    }
}
