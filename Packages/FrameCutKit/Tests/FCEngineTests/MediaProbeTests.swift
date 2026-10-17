import AVFoundation
import XCTest
import FCCore
@testable import FCMedia

final class MediaProbeTests: XCTestCase {
    func testProbeLandscape() async throws {
        let a = try await MediaProbe.probe(url: TestMedia.url("landscape_10s.mp4"))
        XCTAssertEqual(a.kind, .video)
        XCTAssertEqual(a.width, 1920)
        XCTAssertEqual(a.height, 1080)
        XCTAssertEqual(a.duration.seconds, 10, accuracy: 0.1)
        XCTAssertTrue(a.hasAudio)
        XCTAssertEqual(a.frameRate, 30, accuracy: 0.5)
        XCTAssertEqual(a.name, "landscape_10s.mp4")
    }

    func testProbeRotated() async throws {
        let a = try await MediaProbe.probe(url: TestMedia.url("portrait_rotated_6s.mov"))
        XCTAssertEqual(a.width, 1080)
        XCTAssertEqual(a.height, 1920)
    }

    func testProbeImage() async throws {
        let a = try await MediaProbe.probe(url: TestMedia.url("photo.jpg"))
        XCTAssertEqual(a.kind, .image)
        XCTAssertEqual(a.width, 1600)
        XCTAssertEqual(a.height, 1200)
        XCTAssertEqual(a.duration, .zero)
    }

    func testProbeAudio() async throws {
        let a = try await MediaProbe.probe(url: TestMedia.url("tone_20s.m4a"))
        XCTAssertEqual(a.kind, .audio)
        XCTAssertEqual(a.duration.seconds, 20, accuracy: 0.1)
    }

    func testProbeUnsupportedThrows() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("x.txt")
        try "hi".write(to: url, atomically: true, encoding: .utf8)
        do {
            _ = try await MediaProbe.probe(url: url)
            XCTFail("应抛错")
        } catch {}
    }

    func testWaveformNonEmpty() async throws {
        let peaks = await WaveformProvider.shared.peaks(url: try TestMedia.url("tone_20s.m4a"), perSecond: 50)
        XCTAssertEqual(Double(peaks.count), 1000, accuracy: 10)
        XCTAssertGreaterThan(peaks.max() ?? 0, 0.1)
    }

    func testThumbnail() async throws {
        let img = await ThumbnailProvider().thumbnail(url: try TestMedia.url("landscape_10s.mp4"), time: Time(seconds: 2), maxHeight: 60)
        XCTAssertNotNil(img)
        XCTAssertLessThanOrEqual(img!.height, 120)
    }

    func testProbeHLG() async throws {
        let a = try await MediaProbe.probe(url: TestMedia.url("hlg_bands_2s.mov"))
        XCTAssertEqual(a.hdr, .hlg)
    }

    func testProbePQ() async throws {
        let a = try await MediaProbe.probe(url: TestMedia.url("pq_bands_2s.mov"))
        XCTAssertEqual(a.hdr, .pq)
    }

    func testProbeSDRHasNoHDR() async throws {
        let a = try await MediaProbe.probe(url: TestMedia.url("landscape_10s.mp4"))
        XCTAssertNil(a.hdr)
    }

    /// 杜比视界要记下底层传输函数：iPhone 为 HLG，部分相机 / 流媒体为 PQ。
    func testDolbyVisionRecordsBaseTransfer() throws {
        func desc(_ transfer: CFString) throws -> CMFormatDescription {
            var d: CMFormatDescription?
            let ext: [CFString: Any] = [
                kCMFormatDescriptionExtension_TransferFunction: transfer,
                kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms: ["dvcC": Data(count: 24)],
            ]
            CMVideoFormatDescriptionCreate(allocator: nil, codecType: kCMVideoCodecType_HEVC, width: 64, height: 64,
                                           extensions: ext as CFDictionary, formatDescriptionOut: &d)
            return try XCTUnwrap(d)
        }
        XCTAssertEqual(MediaProbe.hdrFormat(try desc(kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG)), .dolbyVision)
        XCTAssertEqual(MediaProbe.hdrFormat(try desc(kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ)), .dolbyVisionPQ)
        XCTAssertTrue(HDRFormat.dolbyVisionPQ.isPQ)
        XCTAssertFalse(HDRFormat.dolbyVision.isPQ)
        XCTAssertEqual(HDRFormat.dolbyVisionPQ.displayName, "杜比视界")
    }
}
