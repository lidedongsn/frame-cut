import AVFoundation
import FCCore
@testable import FCEngine
import VideoToolbox
import XCTest

/// 编码器参数对比（FC_BENCH=1）。
final class EncoderBenchmark: XCTestCase {
    func testEncoderVariants() async throws {
        guard ProcessInfo.processInfo.environment["FC_BENCH"] == "1" else { throw XCTSkip("设置 FC_BENCH=1 运行") }
        let formats: [(String, OSType)] = [("BGRA", kCVPixelFormatType_32BGRA), ("420v", kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)]
        for (w, h) in [(1920, 1080), (3840, 2160)] { for (fmtName, fmt) in formats {
            var pb: CVPixelBuffer?
            CVPixelBufferCreate(nil, w, h, fmt, [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &pb)
            // 填充带噪点的画面，避免编码器对纯色走捷径
            CVPixelBufferLockBaseAddress(pb!, [])
            for plane in 0..<max(1, CVPixelBufferGetPlaneCount(pb!)) {
                let isPlanar = CVPixelBufferIsPlanar(pb!)
                let base = (isPlanar ? CVPixelBufferGetBaseAddressOfPlane(pb!, plane) : CVPixelBufferGetBaseAddress(pb!))!.assumingMemoryBound(to: UInt8.self)
                let bytes = isPlanar ? CVPixelBufferGetBytesPerRowOfPlane(pb!, plane) * CVPixelBufferGetHeightOfPlane(pb!, plane) : CVPixelBufferGetBytesPerRow(pb!) * h
                for i in 0..<bytes { base[i] = UInt8(truncatingIfNeeded: (i &* 2654435761) >> 13) }
            }
            CVPixelBufferUnlockBaseAddress(pb!, [])
            let size = CGSize(width: w, height: h)
            for codec in [ExportSettings.Codec.h264, .hevc] {
                for (label, extra) in [("默认", [String: Any]()),
                                       ("优先速度", [kVTCompressionPropertyKey_PrioritizeEncodingSpeedOverQuality as String: true])] {
                    let frames = 900
                    let t = Date()
                    try await encode(pb!, frames: frames, size: size, codec: codec, extra: extra)
                    let fps = Double(frames) / Date().timeIntervalSince(t)
                    print(String(format: "ENC %dp %@ %@ %@: %.0f fps (%.1fx 30fps 实时)", h, fmtName, codec.rawValue, label, fps, fps / 30))
                }
            }
        } }
    }

    /// 同时开多路编码，看硬件编码器总吞吐是否提升。
    func testParallelEncodeSessions() async throws {
        guard ProcessInfo.processInfo.environment["FC_BENCH"] == "1" else { throw XCTSkip("设置 FC_BENCH=1 运行") }
        for (w, h) in [(1920, 1080), (3840, 2160)] {
            var pb: CVPixelBuffer?
            CVPixelBufferCreate(nil, w, h, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &pb)
            CVPixelBufferLockBaseAddress(pb!, [])
            for plane in 0..<2 {
                let base = CVPixelBufferGetBaseAddressOfPlane(pb!, plane)!.assumingMemoryBound(to: UInt8.self)
                for i in 0..<(CVPixelBufferGetBytesPerRowOfPlane(pb!, plane) * CVPixelBufferGetHeightOfPlane(pb!, plane)) {
                    base[i] = UInt8(truncatingIfNeeded: (i &* 2654435761) >> 13)
                }
            }
            CVPixelBufferUnlockBaseAddress(pb!, [])
            let frame = pb!
            let size = CGSize(width: w, height: h)
            for codec in [ExportSettings.Codec.h264, .hevc] {
                for sessions in [1, 2, 3] {
                    let frames = 600
                    let t = Date()
                    try await withThrowingTaskGroup(of: Void.self) { g in
                        for _ in 0..<sessions {
                            g.addTask { try await self.encode(frame, frames: frames, size: size, codec: codec, extra: [:]) }
                        }
                        try await g.waitForAll()
                    }
                    let fps = Double(frames * sessions) / Date().timeIntervalSince(t)
                    print(String(format: "PAR %dp %@ %d 路: 总 %.0f fps", h, codec.rawValue, sessions, fps))
                }
            }
        }
    }

    private func encode(_ frame: CVPixelBuffer, frames: Int, size: CGSize, codec: ExportSettings.Codec, extra: [String: Any]) async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("fc-enc-\(UUID()).mp4")
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        var settings = Exporter.videoSettings(ExportSettings(shortSide: Int(min(size.width, size.height)), codec: codec), size: size)
        var comp = settings[AVVideoCompressionPropertiesKey] as! [String: Any]
        comp.merge(extra) { $1 }
        settings[AVVideoCompressionPropertiesKey] = comp
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        var i = 0
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            input.requestMediaDataWhenReady(on: DispatchQueue(label: "enc")) {
                while input.isReadyForMoreMediaData {
                    if i >= frames { input.markAsFinished(); c.resume(); return }
                    adaptor.append(frame, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: 30))
                    i += 1
                }
            }
        }
        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed, writer.error?.localizedDescription ?? "")
    }
}
