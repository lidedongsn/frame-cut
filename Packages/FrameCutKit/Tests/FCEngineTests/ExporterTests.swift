import AVFoundation
import FCCore
@testable import FCEngine
import XCTest

final class ExporterTests: XCTestCase {
    func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("fc-export-\(UUID().uuidString).mp4")
    }

    func testExport720p() async throws {
        var p = try await Fixtures.project(["landscape_10s.mp4", "photo.jpg"])
        p.transitions[p.mainTrack[1].id] = Transition(kind: .dissolve, duration: Time(seconds: 1))
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let progress = ProgressBox()
        try await Exporter().export(project: p, settings: ExportSettings(shortSide: 720, frameRate: 30, codec: .h264), to: url) {
            progress.set($0)
        }
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        XCTAssertEqual(duration.seconds, 12, accuracy: 0.1)
        let track = try await asset.loadTracks(withMediaType: .video).first!
        let size = try await track.load(.naturalSize)
        XCTAssertEqual(size, CGSize(width: 1280, height: 720))
        let audio = try await asset.loadTracks(withMediaType: .audio)
        XCTAssertFalse(audio.isEmpty)
        XCTAssertEqual(progress.value, 1, accuracy: 0.01)
    }

    func testExportCancelRemovesFile() async throws {
        let p = try await Fixtures.project(["landscape_10s.mp4", "landscape_10s.mp4"])
        let url = tempURL()
        let task = Task {
            try await Exporter().export(project: p, settings: ExportSettings(shortSide: 1080, frameRate: 30, codec: .hevc), to: url) { _ in }
        }
        try await Task.sleep(nanoseconds: 300_000_000)
        task.cancel()
        do {
            try await task.value
            XCTFail("应被取消")
        } catch is CancellationError {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testExportEmptyThrows() async throws {
        do {
            try await Exporter().export(project: Project(name: "e"), settings: ExportSettings(shortSide: 720, frameRate: 30, codec: .h264),
                                        to: tempURL()) { _ in }
            XCTFail()
        } catch CompositionError.empty {}
    }

    func testAudioExtractorLength() async throws {
        let p = try await Fixtures.project(["landscape_10s.mp4"])
        let samples = try await AudioExtractor.mainTrackSamples(project: p)
        XCTAssertEqual(Double(samples.count), 160_000, accuracy: 2_000)
        XCTAssertGreaterThan(samples.map(abs).max() ?? 0, 0.1)
    }

    func testAudioExtractorSilentForImages() async throws {
        let p = try await Fixtures.project(["photo.jpg"])
        let samples = try await AudioExtractor.mainTrackSamples(project: p)
        XCTAssertTrue(samples.isEmpty)
    }
}

final class ProgressBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = 0.0
    var value: Double { lock.lock(); defer { lock.unlock() }; return _value }
    func set(_ v: Double) { lock.lock(); _value = v; lock.unlock() }
}
