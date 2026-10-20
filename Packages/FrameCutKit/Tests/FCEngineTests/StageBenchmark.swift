import AVFoundation
import FCCore
@testable import FCEngine
import FCMedia
import XCTest

/// 导出各阶段拆分测速（FC_BENCH=1）：解码 / 解码+渲染 / 编码 / 完整导出，并统计 CPU 占用。
final class StageBenchmark: XCTestCase {
    private func cpuSeconds() -> Double {
        var u = rusage()
        getrusage(RUSAGE_SELF, &u)
        return Double(u.ru_utime.tv_sec + u.ru_stime.tv_sec) + Double(u.ru_utime.tv_usec + u.ru_stime.tv_usec) / 1e6
    }

    private func measure(_ label: String, seconds media: Double, _ body: () async throws -> Void) async rethrows {
        let c0 = cpuSeconds(), t0 = Date()
        try await body()
        let wall = Date().timeIntervalSince(t0), cpu = cpuSeconds() - c0
        print(String(format: "STAGE %-28@ %6.1fs  %5.1fx realtime  CPU %4.0f%% (≈%.1f 核)", label as NSString, wall, media / wall, cpu / wall * 100, cpu / wall))
    }

    private func project(_ file: String) async throws -> Project {
        var p = try await Fixtures.project([file])
        for i in stride(from: 9.0, to: 180, by: 9) { _ = p.splitMain(at: Time(seconds: i)) }
        p.applyTransitionToAll(FCCore.Transition(kind: .dissolve, duration: Time(seconds: 0.5)))
        p.applyFilterToAll(FilterSettings(preset: .film))
        for i in 0..<40 { p.addSubtitle(at: Time(seconds: Double(i) * 4), text: "第 \(i + 1) 条字幕测试") }
        return p
    }

    func testStages1080p() async throws { try await stages(shortSide: 1080) }
    func testStages4K() async throws { try await stages(shortSide: 2160) }

    private func stages(shortSide: Int) async throws {
        guard ProcessInfo.processInfo.environment["FC_BENCH"] == "1" else { throw XCTSkip("设置 FC_BENCH=1 运行") }
        let file = "vlog_180s.mp4"
        let p = try await project(file)
        let media = TimelineLayout(project: p).duration.seconds
        let size = RenderSize.size(aspect: p.aspect, shortSide: shortSide)
        print("STAGE ---- \(Int(size.width))x\(Int(size.height)), \(String(format: "%.0f", media))s, \(p.mainTrack.count) 段 + 转场 + 滤镜 + 字幕")

        // 1. 纯解码（源文件，不合成）
        try await measure("1 解码", seconds: 180) {
            let asset = AVURLAsset(url: try TestMedia.url(file))
            let reader = try AVAssetReader(asset: asset)
            let out = AVAssetReaderTrackOutput(track: try await asset.loadTracks(withMediaType: .video)[0], outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            ])
            out.alwaysCopiesSampleData = false
            reader.add(out)
            reader.startReading()
            while out.copyNextSampleBuffer() != nil {}
        }

        // 2. 解码 + 合成渲染（不编码）
        var lastFrame: CVPixelBuffer?
        try await measure("2 解码+渲染", seconds: media) {
            let built = try await CompositionBuilder.build(project: p, renderSize: size)
            let reader = try AVAssetReader(asset: built.composition)
            let out = AVAssetReaderVideoCompositionOutput(videoTracks: try await built.composition.loadTracks(withMediaType: .video), videoSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            ])
            out.videoComposition = built.makeVideoComposition(project: p, renderSize: size)
            out.alwaysCopiesSampleData = false
            reader.add(out)
            reader.startReading()
            while let s = out.copyNextSampleBuffer() { lastFrame = CMSampleBufferGetImageBuffer(s) }
        }

        // 3. 纯编码（同一帧重复送入硬件编码器）
        guard let frame = lastFrame else { return XCTFail("没有渲染出帧") }
        let frames = Int(media * 30)
        try await measure("3 编码 H.264", seconds: media) {
            try await encode(frame, frames: frames, size: size, codec: .h264)
        }

        // 4. 完整导出
        try await measure("4 完整导出 H.264", seconds: media) {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("fc-stage.mp4")
            defer { try? FileManager.default.removeItem(at: url) }
            try await Exporter().export(project: p, settings: ExportSettings(shortSide: shortSide, frameRate: 30, codec: .h264), to: url) { _ in }
        }
    }

    private func encode(_ frame: CVPixelBuffer, frames: Int, size: CGSize, codec: ExportSettings.Codec) async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("fc-enc.mp4")
        try? FileManager.default.removeItem(at: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: Exporter.videoSettings(ExportSettings(shortSide: Int(min(size.width, size.height)), codec: codec), size: size))
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        var i = 0
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            input.requestMediaDataWhenReady(on: DispatchQueue(label: "enc")) {
                while input.isReadyForMoreMediaData {
                    if i >= frames {
                        input.markAsFinished()
                        c.resume()
                        return
                    }
                    adaptor.append(frame, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: 30))
                    i += 1
                }
            }
        }
        await writer.finishWriting()
    }
}
