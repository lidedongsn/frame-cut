@testable import FCCore
import XCTest

/// 多音轨：配乐、旁白、音效可以同时放在不同的音频轨上；同一条轨上不重叠。
final class AudioLaneTests: XCTestCase {
    private func t(_ s: Double) -> Time { Time(seconds: s) }

    /// 一个 10 秒片段，加三段 20 / 5 / 5 秒的音频素材。
    private func project() -> (Project, [UUID]) {
        var p = makeProject(clipSeconds: [10])
        let ids = [20.0, 5, 5].enumerated().map { i, seconds -> UUID in
            let a = MediaAsset(kind: .audio, name: "a\(i)", path: "/a\(i)", duration: t(seconds), width: 0, height: 0, hasAudio: true, frameRate: 0)
            p.assets.append(a)
            return a.id
        }
        return (p, ids)
    }

    private func lanes(_ p: Project) -> [String] {
        p.musicTrack.map { "\(p.asset(id: $0.assetID)!.name)@\($0.lane)" }
    }

    func testOverlappingAudioGoesToNextLane() {
        var (p, a) = project()
        p.addMusic(assetID: a[0], at: .zero)           // 配乐 0–20
        p.addMusic(assetID: a[1], at: t(2))            // 旁白 2–7：与配乐重叠
        p.addMusic(assetID: a[2], at: t(8))            // 音效 8–13：与配乐重叠，与旁白不重叠
        XCTAssertEqual(lanes(p), ["a0@0", "a1@1", "a2@1"])
        XCTAssertEqual(p.audioLaneCount, 2)
    }

    func testNonOverlappingAudioStaysOnFirstLane() {
        var (p, a) = project()
        p.addMusic(assetID: a[1], at: .zero)
        p.addMusic(assetID: a[2], at: t(5))
        XCTAssertEqual(lanes(p), ["a1@0", "a2@0"])
    }

    func testMovingIntoOccupiedLaneBumpsToNextFreeLane() {
        var (p, a) = project()
        p.addMusic(assetID: a[1], at: .zero)
        let b = p.addMusic(assetID: a[2], at: t(10))!
        p.updateMusic(id: b) { $0.start = t(3) }
        XCTAssertEqual(p.music(id: b)?.lane, 1, "移到被占的位置时换到下一条轨")
        p.updateMusic(id: b) { $0.start = t(10); $0.lane = 0 }
        XCTAssertEqual(p.music(id: b)?.lane, 0, "移开后可以放回第一条轨")
    }

    func testMovingToNewLaneBelow() {
        var (p, a) = project()
        p.addMusic(assetID: a[1], at: .zero)
        let b = p.addMusic(assetID: a[2], at: t(10))!
        p.updateMusic(id: b) { $0.lane = 1 }
        XCTAssertEqual(p.music(id: b)?.lane, 1, "可以单独放到下一条轨")
        p.updateMusic(id: b) { $0.lane = 3 }
        XCTAssertEqual(p.music(id: b)?.lane, 1, "中间的空轨会被收拢，不留空行")
    }

    func testRemovingClipCompactsEmptyLanes() {
        var (p, a) = project()
        let bgm = p.addMusic(assetID: a[0], at: .zero)!
        p.addMusic(assetID: a[1], at: t(2))
        p.removeMusic(id: bgm)
        XCTAssertEqual(lanes(p), ["a1@0"])
    }

    func testSplitKeepsLane() {
        var (p, a) = project()
        p.addMusic(assetID: a[0], at: .zero)
        let vo = p.addMusic(assetID: a[1], at: t(2))!
        let second = p.splitMusic(id: vo, at: t(4))!
        XCTAssertEqual(p.music(id: second)?.lane, 1)
        XCTAssertEqual(p.music(id: vo)?.lane, 1)
    }

    func testOldProjectsWithOverlappingMusicAreSpreadOnOpen() throws {
        var (p, a) = project()
        p.addMusic(assetID: a[0], at: .zero)
        p.addMusic(assetID: a[1], at: t(2))
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(p)) as! [String: Any]
        json["musicTrack"] = (json["musicTrack"] as! [[String: Any]]).map { var c = $0; c["lane"] = nil; return c }
        let decoded = try JSONDecoder().decode(Project.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(lanes(decoded), ["a0@0", "a1@1"], "旧工程没有轨道信息，重叠的音频自动分开")
    }
}
