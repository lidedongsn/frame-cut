import XCTest
@testable import FCCore

final class ModelTests: XCTestCase {
    func testTimeArithmetic() {
        XCTAssertEqual(Time(seconds: 1.5).microseconds, 1_500_000)
        XCTAssertEqual(Time(seconds: 2) / 2.0, Time(seconds: 1))
        XCTAssertEqual(Time(seconds: 1) * 3.0, Time(seconds: 3))
        XCTAssertEqual(Time(seconds: 1) + Time(seconds: 2), Time(seconds: 3))
        XCTAssertEqual(Time(Time(seconds: 2.5).cmTime), Time(seconds: 2.5))
    }

    func testClipTimelineDuration() {
        var clip = VideoClip(assetID: UUID(), sourceIn: .zero, sourceOut: Time(seconds: 4))
        clip.speed = 2
        XCTAssertEqual(clip.sourceDuration, Time(seconds: 4))
        XCTAssertEqual(clip.timelineDuration, Time(seconds: 2))
    }

    func testProjectRoundTrip() throws {
        var p = Project(name: "测试")
        let asset = MediaAsset(kind: .video, name: "a.mp4", path: "/tmp/a.mp4", duration: Time(seconds: 10),
                               width: 1920, height: 1080, hasAudio: true, frameRate: 30)
        p.assets.append(asset)
        let clip = VideoClip(assetID: asset.id, sourceIn: .zero, sourceOut: Time(seconds: 5))
        p.mainTrack.append(clip)
        p.transitions[clip.id] = Transition(kind: .dissolve, duration: Time(seconds: 0.5))
        p.subtitles.append(Subtitle(start: .zero, end: Time(seconds: 1), text: "你好"))
        let data = try JSONEncoder().encode(p)
        let back = try JSONDecoder().decode(Project.self, from: data)
        XCTAssertEqual(back, p)
    }
}
