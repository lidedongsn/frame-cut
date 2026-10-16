import AVFoundation
import FCCore
@testable import FCEngine
import FCMedia
import XCTest

/// 性能实测：FC_BENCH=1 时运行。3 分钟 1080p，20 段 + 转场 + 滤镜 + 音乐 + 字幕。
final class Benchmark: XCTestCase {
    func testExport3MinVlog1080p() async throws {
        try await run(file: "vlog_180s.mp4", range: .sdr)
    }

    func testExport3MinHLGVlog1080pAsHDR() async throws {
        try await run(file: "vlog_hlg_180s.mov", range: .hlg)
    }

    func testExport3MinHLGVlog1080pAsSDR() async throws {
        try await run(file: "vlog_hlg_180s.mov", range: .sdr)
    }

    private func run(file: String, range: DynamicRangeOutput) async throws {
        guard ProcessInfo.processInfo.environment["FC_BENCH"] == "1" else { throw XCTSkip("设置 FC_BENCH=1 运行") }
        var p = try await Fixtures.project([file])
        for i in stride(from: 9.0, to: 180, by: 9) { _ = p.splitMain(at: Time(seconds: i)) }
        p.applyTransitionToAll(FCCore.Transition(kind: .dissolve, duration: Time(seconds: 0.5)))
        p.applyFilterToAll(FilterSettings(preset: .film))
        let music = try await MediaProbe.probe(url: TestMedia.url("tone_20s.m4a"))
        p.assets.append(music)
        p.addMusic(assetID: music.id, at: .zero)
        for i in 0..<40 { p.addSubtitle(at: Time(seconds: Double(i) * 4), text: "第 \(i + 1) 条字幕测试") }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("fc-bench.mp4")
        defer { try? FileManager.default.removeItem(at: url) }
        let start = Date()
        try await Exporter().export(project: p, settings: ExportSettings(shortSide: 1080, frameRate: 30, codec: .h264, dynamicRange: range), to: url) { _ in }
        let elapsed = Date().timeIntervalSince(start)
        let duration = TimelineLayout(project: p).duration.seconds
        print(String(format: "BENCH \(file) → \(range) clips=%d duration=%.1fs export=%.1fs (%.2fx realtime)", p.mainTrack.count, duration, elapsed, duration / elapsed))
        XCTAssertLessThan(elapsed, duration, "导出应快于实时")
    }
}
