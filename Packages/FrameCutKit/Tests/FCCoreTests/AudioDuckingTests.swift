@testable import FCCore
import XCTest

/// 人声避让：在「人声区间」内把开启避让的音频调低；区间可手动编辑，也可按字幕或声音生成。
/// 以及整条音频轨的静音与音量。
@MainActor
final class AudioDuckingTests: XCTestCase {
    private func t(_ s: Double) -> Time { Time(seconds: s) }

    /// 一个 30 秒片段 + 一段 30 秒配乐（音量 0.8，开启避让）。
    private func project() -> (Project, UUID) {
        var p = makeProject(clipSeconds: [30])
        let a = MediaAsset(kind: .audio, name: "bgm", path: "/bgm", duration: t(30), width: 0, height: 0, hasAudio: true, frameRate: 0)
        p.assets.append(a)
        let id = p.addMusic(assetID: a.id, at: .zero)!
        p.updateMusic(id: id) { $0.volume = 0.8; $0.ducks = true }
        return (p, id)
    }

    private func gain(_ p: Project, _ id: UUID, at s: Double) -> Double {
        p.volumeEnvelope(for: p.music(id: id)!).gain(at: t(s))
    }

    // MARK: 区间编辑

    func testAddUpdateRemoveDuckRange() {
        var (p, _) = project()
        let a = p.addDuckRange(at: t(5))
        XCTAssertEqual(p.duckRanges.first?.start, t(5))
        XCTAssertEqual(p.duckRanges.first?.end, t(5) + DuckRange.defaultDuration)
        p.updateDuckRange(id: a) { $0.start = t(-1) }
        XCTAssertEqual(p.duckRanges.first?.start, .zero)
        p.removeDuckRange(id: a)
        XCTAssertEqual(p.duckRanges, [])
    }

    func testRangesFromSubtitlesMergeShortGaps() {
        var (p, _) = project()
        p.replaceSubtitles([Subtitle(start: t(1), end: t(3), text: "a"),
                            Subtitle(start: t(3.2), end: t(5), text: "b"),   // 间隔 0.2 秒 → 合并
                            Subtitle(start: t(10), end: t(12), text: "c")])
        p.replaceDuckRanges(DuckRange.merged(p.subtitles.map { ($0.start, $0.end) }))
        XCTAssertEqual(p.duckRanges.map { [$0.start.seconds, $0.end.seconds] }, [[1, 5], [10, 12]])
    }

    func testOldProjectsDecodeWithoutDucking() throws {
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(project().0)) as! [String: Any]
        json["duckRanges"] = nil
        json["duck"] = nil
        json["audioLanes"] = nil
        json["musicTrack"] = (json["musicTrack"] as! [[String: Any]]).map { var c = $0; c["ducks"] = nil; return c }
        let p = try JSONDecoder().decode(Project.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(p.duckRanges, [])
        XCTAssertEqual(p.duck, DuckSettings())
        XCTAssertFalse(p.musicTrack[0].ducks)
    }

    // MARK: 音量包络

    func testDuckingLowersVolumeInsideRangesWithFades() {
        var (p, id) = project()
        p.duck.level = 0.25
        p.duck.fade = 0.5
        p.addDuckRange(at: t(10))   // 10–12 秒
        XCTAssertEqual(gain(p, id, at: 5), 0.8, accuracy: 0.001)
        XCTAssertEqual(gain(p, id, at: 11), 0.2, accuracy: 0.001, "区间内调低到 25%")
        XCTAssertEqual(gain(p, id, at: 9.75), 0.5, accuracy: 0.001, "进入前 0.5 秒渐变，一半处")
        XCTAssertEqual(gain(p, id, at: 12.25), 0.5, accuracy: 0.001, "离开后渐变回来")
        XCTAssertEqual(gain(p, id, at: 13), 0.8, accuracy: 0.001)
    }

    func testClipWithoutDuckingIgnoresRanges() {
        var (p, id) = project()
        p.updateMusic(id: id) { $0.ducks = false }
        p.addDuckRange(at: t(10))
        XCTAssertEqual(gain(p, id, at: 11), 0.8, accuracy: 0.001)
    }

    func testDuckingCombinesWithClipFades() {
        var (p, id) = project()
        p.updateMusic(id: id) { $0.fadeIn = Time(seconds: 2) }
        p.duck.level = 0.5
        p.duck.fade = 0.2
        p.addDuckRange(at: .zero)   // 0–2 秒，和淡入重叠
        XCTAssertEqual(gain(p, id, at: 1), 0.8 * 0.5 * 0.5, accuracy: 0.001, "淡入一半 × 调低一半")
        XCTAssertEqual(gain(p, id, at: 0), 0, accuracy: 0.001)
    }

    func testEnvelopeIsRelativeToClipTimeline() {
        var (p, id) = project()
        p.updateMusic(id: id) { $0.start = t(20) }   // 配乐从 20 秒开始
        p.addDuckRange(at: t(25))
        XCTAssertEqual(gain(p, id, at: 26), 0.8 * p.duck.level, accuracy: 0.001)
        XCTAssertEqual(p.volumeEnvelope(for: p.music(id: id)!).points.first?.time, t(20))
    }

    // MARK: 整条轨

    func testLaneMuteAndVolume() {
        var (p, id) = project()
        p.updateAudioLane(0) { $0.volume = 0.5 }
        XCTAssertEqual(gain(p, id, at: 5), 0.4, accuracy: 0.001)
        p.updateAudioLane(0) { $0.muted = true }
        XCTAssertEqual(gain(p, id, at: 5), 0, accuracy: 0.001)
        p.updateMusic(id: id) { $0.muted = true }
        p.updateAudioLane(0) { $0.muted = false }
        XCTAssertEqual(gain(p, id, at: 5), 0, accuracy: 0.001, "片段自己静音")
    }

    func testLaneSettingsMoveWithLaneWhenCompacted() {
        var (p, bgm) = project()
        let voice = p.addMusic(assetID: p.music(id: bgm)!.assetID, at: t(1))!
        XCTAssertEqual(p.music(id: voice)?.lane, 1)
        p.updateAudioLane(1) { $0.volume = 0.3 }
        p.removeMusic(id: bgm)   // 第一条轨空了，第二条收拢为第一条
        XCTAssertEqual(p.music(id: voice)?.lane, 0)
        XCTAssertEqual(p.laneSettings(0).volume, 0.3, accuracy: 0.001, "设置跟着轨道走")
    }

    // MARK: 跟随主轨

    func testDuckRangesFollowMainEdits() {
        var p = makeProject(clipSeconds: [10, 10])
        p.addDuckRange(at: t(12))
        let s = EditorStore(project: p)
        s.perform { $0.removeMain(id: $0.mainTrack[0].id) }
        XCTAssertEqual(s.project.duckRanges.map(\.start), [t(2)])
    }

    // MARK: 按声音检测

    func testSpeechDetectionFindsLoudStretchesAboveNoise() {
        let rate = 16_000
        var samples = [Float](repeating: 0, count: rate * 6)
        var rng = SystemRandomNumberGenerator()
        for i in samples.indices { samples[i] = Float.random(in: -0.003...0.003, using: &rng) }   // 环境底噪
        func speak(_ from: Double, _ to: Double) {
            for i in Int(from * Double(rate))..<Int(to * Double(rate)) {
                samples[i] += 0.3 * sin(Float(i) * 2 * .pi * 220 / Float(rate))
            }
        }
        speak(1, 2)
        speak(2.2, 2.8)   // 间隔 0.2 秒，与上一段合并
        speak(4.5, 5)
        let ranges = SpeechDetector.ranges(samples: samples, sampleRate: rate)
        XCTAssertEqual(ranges.count, 2)
        XCTAssertEqual(ranges[0].start.seconds, 1, accuracy: 0.15)
        XCTAssertEqual(ranges[0].end.seconds, 2.8, accuracy: 0.15)
        XCTAssertEqual(ranges[1].start.seconds, 4.5, accuracy: 0.15)
    }

    func testSpeechDetectionOnSilenceIsEmpty() {
        XCTAssertEqual(SpeechDetector.ranges(samples: [Float](repeating: 0, count: 16_000 * 3), sampleRate: 16_000).count, 0)
    }
}
