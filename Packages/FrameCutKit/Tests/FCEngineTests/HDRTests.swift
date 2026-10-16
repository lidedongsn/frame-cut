import AVFoundation
import CoreImage
import FCCore
@testable import FCEngine
import FCMedia
import XCTest

/// 测试素材的四条竖向亮度带中心（相对横坐标）。
let bandX: [Double] = [0.125, 0.375, 0.625, 0.875]

enum HDRFixtures {
    /// 解码第一帧为 10 位 x420。
    static func firstFrame(_ name: String) async throws -> CVPixelBuffer {
        let asset = AVURLAsset(url: try TestMedia.url(name))
        let track = try await asset.loadTracks(withMediaType: .video).first!
        let reader = try AVAssetReader(asset: asset)
        let out = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange,
        ])
        reader.add(out)
        reader.startReading()
        return CMSampleBufferGetImageBuffer(out.copyNextSampleBuffer()!)!
    }

    static func instruction(colorMode: ColorMode, output: DynamicRangeOutput, isHDR: Bool = true,
                            subtitles: [Subtitle] = [], layers: Bool = true) -> RenderInstruction {
        let layer = LayerSpec(source: .track(1), naturalSize: CGSize(width: 1920, height: 1080), preferredTransform: .identity,
                              transform: ClipTransform(), filter: FilterSettings(), isHDR: isHDR)
        return RenderInstruction(timeRange: CMTimeRange(start: .zero, duration: CMTime(value: 1, timescale: 1)),
                                 layers: layers ? [layer] : [], transition: nil,
                                 scene: RenderScene(subtitles: subtitles, style: SubtitleStyle()),
                                 trackIDs: [1], output: output, colorMode: colorMode)
    }

    /// 合成一帧，返回各亮度带中心的线性值（R 通道，1.0 = 203 尼特）。
    static func bands(_ instruction: RenderInstruction, source: CVPixelBuffer?) -> [Float] {
        let canvas = CGSize(width: 640, height: 360)
        let image = FrameRenderer.shared.composeFrame(instruction: instruction, time: .zero, canvas: canvas) { _ in source }
        return bandX.map { x in
            var px = [Float](repeating: 0, count: 4)
            FrameRenderer.shared.context.render(image, toBitmap: &px, rowBytes: 16,
                                                bounds: CGRect(x: Double(canvas.width) * x, y: 180, width: 1, height: 1),
                                                format: .RGBAf, colorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!)
            return px[0]
        }
    }

    /// 导出文件第一帧的 Y 码值（10 位或 8 位）与格式描述。
    static func exportedLuma(_ url: URL) async throws -> (luma: [Int], format: CMFormatDescription) {
        let asset = AVURLAsset(url: url)
        let track = try await asset.loadTracks(withMediaType: .video).first!
        let format = try await track.load(.formatDescriptions).first!
        let reader2 = try AVAssetReader(asset: asset)
        let hdrTransfers = [kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG as String, kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ as String]
        let is10 = transfer(format).map(hdrTransfers.contains) ?? false
        let out2 = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: is10 ? kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange : kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
        ])
        reader2.add(out2)
        reader2.startReading()
        let buffer = CMSampleBufferGetImageBuffer(out2.copyNextSampleBuffer()!)!
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let w = CVPixelBufferGetWidthOfPlane(buffer, 0), h = CVPixelBufferGetHeightOfPlane(buffer, 0)
        let base = CVPixelBufferGetBaseAddressOfPlane(buffer, 0)!
        let stride = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
        let luma = bandX.map { x -> Int in
            let px = Int(Double(w) * x), py = h / 2
            if is10 {
                return Int(base.advanced(by: py * stride + px * 2).assumingMemoryBound(to: UInt16.self).pointee >> 6)
            }
            return Int(base.advanced(by: py * stride + px).assumingMemoryBound(to: UInt8.self).pointee)
        }
        return (luma, format)
    }

    static func transfer(_ f: CMFormatDescription) -> String? {
        CMFormatDescriptionGetExtension(f, extensionKey: kCMFormatDescriptionExtension_TransferFunction) as? String
    }
}

final class HDRRenderTests: XCTestCase {
    func testHLGSourceKeepsHighlightsInHDROutput() async throws {
        let src = try await HDRFixtures.firstFrame("hlg_bands_2s.mov")
        let v = HDRFixtures.bands(HDRFixtures.instruction(colorMode: .hdr, output: .hlg), source: src)
        XCTAssertEqual(v[1], 1.0, accuracy: 0.06, "HLG 0.75 应为参考白")
        XCTAssertGreaterThan(v[3], 4.0, "1000 尼特高光不应被截断：\(v)")
    }

    func testPQSourceDecodesAbsoluteLuminance() async throws {
        let src = try await HDRFixtures.firstFrame("pq_bands_2s.mov")
        let v = HDRFixtures.bands(HDRFixtures.instruction(colorMode: .hdr, output: .pq), source: src)
        XCTAssertEqual(v[1], 1.0, accuracy: 0.06)        // 203 尼特
        XCTAssertEqual(v[3], 4.93, accuracy: 0.3)        // 1000 尼特
    }

    func testSDROutputToneMapsHDRProject() async throws {
        let src = try await HDRFixtures.firstFrame("hlg_bands_2s.mov")
        let v = HDRFixtures.bands(HDRFixtures.instruction(colorMode: .hdr, output: .sdr), source: src)
        assertToneMapped(v)
    }

    func testSDRProjectToneMapsHDRSource() async throws {
        let src = try await HDRFixtures.firstFrame("hlg_bands_2s.mov")
        let v = HDRFixtures.bands(HDRFixtures.instruction(colorMode: .sdr, output: .sdr), source: src)
        assertToneMapped(v)
    }

    func testSubtitleAtReferenceWhiteInHDR() {
        let sub = Subtitle(start: .zero, end: Time(seconds: 1), text: "██████████")
        var style = SubtitleStyle()
        style.verticalPosition = 0.5
        style.strokeWidth = 0
        let instruction = RenderInstruction(timeRange: CMTimeRange(start: .zero, duration: CMTime(value: 1, timescale: 1)), layers: [],
                                            transition: nil, scene: RenderScene(subtitles: [sub], style: style), trackIDs: [],
                                            output: .hlg, colorMode: .hdr)
        let image = FrameRenderer.shared.composeFrame(instruction: instruction, time: Time(seconds: 0.5), canvas: CGSize(width: 640, height: 360)) { _ in nil }
        // 取字幕区域内最大值（避开字形边缘的抗锯齿）
        var px = [Float](repeating: 0, count: 200 * 20 * 4)
        FrameRenderer.shared.context.render(image, toBitmap: &px, rowBytes: 200 * 16, bounds: CGRect(x: 220, y: 170, width: 200, height: 20),
                                            format: .RGBAf, colorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!)
        let peak = stride(from: 0, to: px.count, by: 4).map { px[$0] }.max() ?? 0
        XCTAssertEqual(peak, 1.0, accuracy: 0.05, "HDR 中白色字幕应在参考白，而非峰值")
    }

    private func assertToneMapped(_ v: [Float], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(zip(v, v.dropFirst()).allSatisfy { $0 < $1 }, true, "应严格递增：\(v)", file: file, line: line)
        XCTAssertLessThanOrEqual(v[3], 1.05, file: file, line: line)
        XCTAssertGreaterThan(v[3] - v[2], 0.015, "400 与 1000 尼特应可区分：\(v)", file: file, line: line)
        XCTAssertEqual(v[1], Float(ToneMap.map(1.0)), accuracy: 0.05, file: file, line: line)
    }
}

final class HDRExportTests: XCTestCase {
    func tempURL() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("fc-hdr-\(UUID().uuidString).mov") }

    func testHDRProjectFromHLGSource() async throws {
        let p = try await Fixtures.project(["hlg_bands_2s.mov"])
        XCTAssertEqual(p.colorMode, .hdr)
    }

    func testExportHLG() async throws {
        let p = try await Fixtures.project(["hlg_bands_2s.mov"])
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try await Exporter().export(project: p, settings: ExportSettings(shortSide: 1080, frameRate: 30, codec: .h264, dynamicRange: .hlg), to: url) { _ in }
        let (luma, format) = try await HDRFixtures.exportedLuma(url)
        XCTAssertEqual(CMFormatDescriptionGetMediaSubType(format), kCMVideoCodecType_HEVC, "HDR 应强制 HEVC")
        XCTAssertEqual(HDRFixtures.transfer(format), kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG as String)
        XCTAssertEqual(CMFormatDescriptionGetExtension(format, extensionKey: kCMFormatDescriptionExtension_ColorPrimaries) as? String,
                       kCMFormatDescriptionColorPrimaries_ITU_R_2020 as String)
        XCTAssertEqual(luma[1], 721, accuracy: 15, "参考白 \(luma)")
        XCTAssertEqual(luma[3], 940, accuracy: 15, "峰值 \(luma)")
    }

    func testExportPQ() async throws {
        let p = try await Fixtures.project(["hlg_bands_2s.mov"])
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try await Exporter().export(project: p, settings: ExportSettings(shortSide: 1080, frameRate: 30, codec: .hevc, dynamicRange: .pq), to: url) { _ in }
        let (luma, format) = try await HDRFixtures.exportedLuma(url)
        XCTAssertEqual(HDRFixtures.transfer(format), kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ as String)
        XCTAssertEqual(luma[1], 64 + Int(876 * PQ.encode(203)), accuracy: 15, "203 尼特 \(luma)")
        XCTAssertEqual(luma[3], 64 + Int(876 * PQ.encode(1000)), accuracy: 15, "1000 尼特 \(luma)")
    }

    func testExportSDRFromHDRProject() async throws {
        let p = try await Fixtures.project(["hlg_bands_2s.mov"])
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try await Exporter().export(project: p, settings: ExportSettings(shortSide: 1080, frameRate: 30, codec: .h264, dynamicRange: .sdr), to: url) { _ in }
        let (luma, format) = try await HDRFixtures.exportedLuma(url)
        XCTAssertEqual(CMFormatDescriptionGetMediaSubType(format), kCMVideoCodecType_H264)
        XCTAssertNotEqual(HDRFixtures.transfer(format), kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG as String)
        XCTAssertTrue(zip(luma, luma.dropFirst()).allSatisfy { $0 < $1 }, "色调映射后亮度应递增：\(luma)")
        XCTAssertLessThan(luma[2], 235, "400 尼特不应截成纯白：\(luma)")
    }
}

final class HDRThumbnailTests: XCTestCase {
    func testHDRThumbnailIsToneMapped() async throws {
        ThumbnailProvider.hdrToneMapper = HDRThumbnail.toneMap
        let img = await ThumbnailProvider().thumbnail(url: try TestMedia.url("hlg_bands_2s.mov"), time: Time(seconds: 0.5),
                                                      maxHeight: 90, hdr: .hlg)
        let thumb = try XCTUnwrap(img)
        let v = bandX.map { Fixtures.pixel(thumb, x: $0, y: 0.5).0 }
        XCTAssertTrue(zip(v, v.dropFirst()).allSatisfy { $0 < $1 }, "色调映射后各亮度带应递增：\(v)")
        XCTAssertLessThan(v[2], 252, "400 尼特不应截成纯白：\(v)")
    }
}
