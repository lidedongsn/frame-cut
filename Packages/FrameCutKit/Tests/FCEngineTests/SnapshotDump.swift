import AVFoundation
import FCCore
@testable import FCEngine
import ImageIO
import UniformTypeIdentifiers
import XCTest

/// 手动查看用：FC_DUMP_DIR 设置时把几帧写成 PNG。
final class SnapshotDump: XCTestCase {
    func testDumpFrames() async throws {
        guard let dir = ProcessInfo.processInfo.environment["FC_DUMP_DIR"] else { throw XCTSkip("未设置 FC_DUMP_DIR") }
        var p = try await Fixtures.project(["landscape_10s.mp4", "photo.jpg"])
        p.transitions[p.mainTrack[1].id] = Transition(kind: .pushLeft, duration: Time(seconds: 1))
        p.updateMain(id: p.mainTrack[0].id) { $0.filter = FilterSettings(preset: .cinematic) }
        p.addSubtitle(at: .zero, text: "今天带大家去海边走走", duration: Time(seconds: 12))
        for (name, t) in [("a_filter_sub", 3.0), ("b_push", 9.5)] {
            let img = try await Fixtures.frame(p, at: t, shortSide: 540)
            let url = URL(fileURLWithPath: dir).appendingPathComponent("\(name).png") as CFURL
            let dest = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil)!
            CGImageDestinationAddImage(dest, img, nil)
            CGImageDestinationFinalize(dest)
        }
    }
}
