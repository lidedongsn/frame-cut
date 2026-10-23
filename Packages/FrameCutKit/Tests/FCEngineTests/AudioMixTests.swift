import AVFoundation
import FCCore
@testable import FCEngine
import FCMedia
import XCTest

/// 多音轨混音：不同轨上重叠的音频同时播放；静音的片段音量为 0，取消静音后回到原来的音量。
final class AudioMixTests: XCTestCase {
    private func volume(_ mix: AVAudioMix, track: AVCompositionTrack, at seconds: Double) -> Float? {
        guard let p = mix.inputParameters.first(where: { $0.trackID == track.trackID }) else { return nil }
        var start: Float = 0, end: Float = 0
        var range = CMTimeRange()
        guard p.getVolumeRamp(for: CMTime(seconds: seconds, preferredTimescale: 600), startVolume: &start, endVolume: &end, timeRange: &range) else { return nil }
        return start
    }

    func testOverlappingLanesMixAndMuteKeepsVolume() async throws {
        var p = try await Fixtures.project(["landscape_10s.mp4"])
        let tone = try await MediaProbe.probe(url: TestMedia.url("tone_20s.m4a"))
        p.assets.append(tone)
        let bgm = p.addMusic(assetID: tone.id, at: .zero)!
        let voice = p.addMusic(assetID: tone.id, at: Time(seconds: 2))!
        XCTAssertEqual(p.music(id: voice)?.lane, 1)
        p.updateMusic(id: bgm) { $0.volume = 0.3 }
        p.updateMusic(id: voice) { $0.muted = true }

        let built = try await CompositionBuilder.build(project: p, renderSize: CGSize(width: 64, height: 36))
        let mix = built.makeAudioMix(project: p)
        let bgmTrack = try XCTUnwrap(built.musicTracks[bgm])
        let voiceTrack = try XCTUnwrap(built.musicTracks[voice])
        XCTAssertNotEqual(bgmTrack.trackID, voiceTrack.trackID, "两条轨各自一条合成轨，可以同时播放")
        XCTAssertEqual(try XCTUnwrap(volume(mix, track: bgmTrack, at: 3)), 0.3, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(volume(mix, track: voiceTrack, at: 3)), 0, accuracy: 0.001)

        p.updateMusic(id: voice) { $0.muted = false }
        XCTAssertEqual(p.music(id: voice)?.volume, 1, "静音不改动音量")
    }

    /// 人声避让和整条轨音量写进混音：区间内调低，区间外恢复。
    func testDuckingAndLaneVolumeReachTheMix() async throws {
        var p = try await Fixtures.project(["landscape_10s.mp4"])
        let tone = try await MediaProbe.probe(url: TestMedia.url("tone_20s.m4a"))
        p.assets.append(tone)
        let bgm = p.addMusic(assetID: tone.id, at: .zero)!
        p.updateMusic(id: bgm) { $0.ducks = true }
        p.updateAudioLane(0) { $0.volume = 0.5 }
        p.duck.level = 0.2
        p.addDuckRange(at: Time(seconds: 4))   // 4–6 秒

        let built = try await CompositionBuilder.build(project: p, renderSize: CGSize(width: 64, height: 36))
        let mix = built.makeAudioMix(project: p)
        let track = try XCTUnwrap(built.musicTracks[bgm])
        XCTAssertEqual(try XCTUnwrap(volume(mix, track: track, at: 2)), 0.5, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(volume(mix, track: track, at: 5)), 0.1, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(volume(mix, track: track, at: 8)), 0.5, accuracy: 0.001)
    }
}
