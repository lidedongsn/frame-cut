import AVFoundation
import FCCore
import FCMedia
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

/// 手动验收用：FC_DEMO_DIR 设置时生成一个演示工程 demo.framecut。
final class DemoProjectMaker: XCTestCase {
    func testMakeDemoProject() async throws {
        guard let dir = ProcessInfo.processInfo.environment["FC_DEMO_DIR"] else { throw XCTSkip("未设置 FC_DEMO_DIR") }
        var p = try await Fixtures.project(["landscape_10s.mp4", "photo.jpg", "portrait_rotated_6s.mov"])
        p.name = "演示工程"
        p.transitions[p.mainTrack[1].id] = FCCore.Transition(kind: .dissolve, duration: Time(seconds: 1))
        p.transitions[p.mainTrack[2].id] = FCCore.Transition(kind: .pushLeft, duration: Time(seconds: 0.8))
        p.updateMain(id: p.mainTrack[0].id) { $0.filter = FilterSettings(preset: .warm) }
        let music = try await MediaProbe.probe(url: TestMedia.url("tone_20s.m4a"))
        p.assets.append(music)
        let id = p.addMusic(assetID: music.id, at: .zero)!
        p.updateMusic(id: id) { $0.volume = 0.3; $0.fadeIn = Time(seconds: 1); $0.fadeOut = Time(seconds: 2) }
        p.addSubtitle(at: Time(seconds: 0.5), text: "大家好，欢迎来到我的 vlog")
        p.addSubtitle(at: Time(seconds: 3), text: "今天天气很好")
        try ProjectFile.write(p, to: URL(fileURLWithPath: dir).appendingPathComponent("demo.framecut"))
    }
}
