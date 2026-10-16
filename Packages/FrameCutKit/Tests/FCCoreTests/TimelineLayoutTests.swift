import XCTest
@testable import FCCore

func makeProject(clipSeconds: [Double]) -> Project {
    var p = Project(name: "t")
    let asset = MediaAsset(kind: .video, name: "a", path: "/tmp/a.mp4", duration: Time(seconds: 100),
                           width: 1920, height: 1080, hasAudio: true, frameRate: 30)
    p.assets = [asset]
    p.mainTrack = clipSeconds.map { VideoClip(assetID: asset.id, sourceIn: .zero, sourceOut: Time(seconds: $0)) }
    return p
}

final class TimelineLayoutTests: XCTestCase {
    func testSequentialNoTransitions() {
        let layout = TimelineLayout(project: makeProject(clipSeconds: [3, 2]))
        XCTAssertEqual(layout.placements.map(\.start), [.zero, Time(seconds: 3)])
        XCTAssertEqual(layout.placements.map(\.lane), [0, 1])
        XCTAssertEqual(layout.duration, Time(seconds: 5))
    }

    func testTransitionOverlap() {
        var p = makeProject(clipSeconds: [4, 4])
        p.transitions[p.mainTrack[1].id] = Transition(kind: .dissolve, duration: Time(seconds: 1))
        let layout = TimelineLayout(project: p)
        XCTAssertEqual(layout.placements.map(\.start), [.zero, Time(seconds: 3)])
        XCTAssertEqual(layout.duration, Time(seconds: 7))
        XCTAssertEqual(layout.placements[1].transitionIn?.duration, Time(seconds: 1))
        XCTAssertNil(layout.placements[0].transitionIn)
    }

    func testTransitionClampedForShortClips() {
        var p = makeProject(clipSeconds: [1, 0.6])
        p.transitions[p.mainTrack[1].id] = Transition(kind: .dissolve, duration: Time(seconds: 1))
        let layout = TimelineLayout(project: p)
        XCTAssertEqual(layout.placements[1].transitionIn?.duration, Time(seconds: 0.3))
        XCTAssertEqual(layout.duration, Time(seconds: 1.3))
    }

    func testTransitionOnFirstClipIgnored() {
        var p = makeProject(clipSeconds: [2])
        p.transitions[p.mainTrack[0].id] = Transition(kind: .dissolve)
        XCTAssertNil(TimelineLayout(project: p).placements[0].transitionIn)
    }

    func testSpeedAffectsDuration() {
        var p = makeProject(clipSeconds: [4, 2])
        p.mainTrack[0].speed = 2
        let layout = TimelineLayout(project: p)
        XCTAssertEqual(layout.duration, Time(seconds: 4))
        XCTAssertEqual(layout.placements[1].start, Time(seconds: 2))
    }

    func testClipIndexAt() {
        let layout = TimelineLayout(project: makeProject(clipSeconds: [3, 2]))
        XCTAssertEqual(layout.clipIndex(at: Time(seconds: 1)), 0)
        XCTAssertEqual(layout.clipIndex(at: Time(seconds: 3)), 1)
        XCTAssertEqual(layout.clipIndex(at: Time(seconds: 4.9)), 1)
        XCTAssertNil(layout.clipIndex(at: Time(seconds: 5)))
    }

    func testEmpty() {
        let layout = TimelineLayout(project: Project(name: "e"))
        XCTAssertTrue(layout.placements.isEmpty)
        XCTAssertEqual(layout.duration, .zero)
    }
}
