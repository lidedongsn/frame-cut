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

extension SnapshotDump {
    /// 调色前后对比：阴影提亮、高光压暗、蓝色加饱和、暗角、锐化。
    func testDumpGrading() async throws {
        guard let dir = ProcessInfo.processInfo.environment["FC_DUMP_DIR"] else { throw XCTSkip("未设置 FC_DUMP_DIR") }
        var p = try await Fixtures.project(["landscape_10s.mp4"])
        let before = try await Fixtures.frame(p, at: 3, shortSide: 540)
        p.updateMain(id: p.mainTrack[0].id) {
            $0.filter.shadows = 0.8; $0.filter.highlights = -0.6; $0.filter.vibrance = 0.5
            $0.filter.hsl[.blue] = HSLAdjust(hue: 0.5, saturation: -1, luminance: 0)
            $0.filter.vignette = 0.8; $0.filter.sharpen = 0.6
        }
        let after = try await Fixtures.frame(p, at: 3, shortSide: 540)
        for (name, img) in [("grade_before", before), ("grade_after", after)] {
            let url = URL(fileURLWithPath: dir).appendingPathComponent("\(name).png") as CFURL
            let dest = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil)!
            CGImageDestinationAddImage(dest, img, nil)
            CGImageDestinationFinalize(dest)
        }
    }
}

extension SnapshotDump {
    /// 文字：大标题上浮、地点标签、打字机日期、章节弹出，叠加字幕。
    func testDumpTexts() async throws {
        guard let dir = ProcessInfo.processInfo.environment["FC_DUMP_DIR"] else { throw XCTSkip("未设置 FC_DUMP_DIR") }
        var p = try await Fixtures.project(["landscape_10s.mp4"])
        func style(_ font: String, _ size: Double, x: Double = 0.5, y: Double = 0.5, color: RGBA = .white,
                   stroke: RGBA = .black, strokeWidth: Double = 0, background: RGBA = .clear) -> SubtitleStyle {
            var s = SubtitleStyle()
            s.fontName = font; s.fontSize = size; s.horizontalPosition = x; s.verticalPosition = y
            s.textColor = color; s.strokeColor = stroke; s.strokeWidth = strokeWidth; s.backgroundColor = background
            return s
        }
        func t(_ s: Double) -> Time { Time(seconds: s) }
        p.addText(TextClip(start: t(0), end: t(6), text: "我的周末",
                           style: style("PingFangSC-Semibold", 0.12, y: 0.45, stroke: RGBA(r: 0, g: 0, b: 0, a: 0.6), strokeWidth: 0.06), animation: .rise))
        p.addText(TextClip(start: t(0), end: t(6), text: "📍 京都 · 岚山",
                           style: style("PingFangSC-Semibold", 0.045, x: 0.22, y: 0.88, background: RGBA(r: 0, g: 0, b: 0, a: 0.45)), animation: .rise))
        p.addText(TextClip(start: t(0), end: t(6), text: "2026.10.23", style: style("Futura-Bold", 0.05, x: 0.85, y: 0.1, strokeWidth: 0.1), animation: .typewriter))
        p.addText(TextClip(start: t(6), end: t(9), text: "Day 1",
                           style: style("AvenirNext-Heavy", 0.1, color: RGBA(r: 1, g: 0.86, b: 0.2), strokeWidth: 0.1), animation: .pop))
        p.addSubtitle(at: t(1), text: "今天去了岚山", duration: t(8))
        for (name, s) in [("text_0.15_enter", 0.15), ("text_0.45_typing", 0.45), ("text_3_settled", 3.0), ("text_6.1_pop", 6.1), ("text_7_chapter", 7.0)] {
            let img = try await Fixtures.frame(p, at: s, shortSide: 540)
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
        // 与配乐重叠的第二段音频（模拟旁白），自动放到第二条音频轨
        let voice = p.addMusic(assetID: music.id, at: Time(seconds: 4))!
        p.updateMusic(id: voice) { $0.sourceOut = Time(seconds: 5); $0.volume = 0.8 }
        // 配乐在人声区间（按字幕生成）里调低
        p.updateMusic(id: id) { $0.ducks = true }
        p.addSubtitle(at: Time(seconds: 0.5), text: "大家好，欢迎来到我的 vlog")
        p.addSubtitle(at: Time(seconds: 3), text: "今天天气很好")
        p.replaceDuckRanges(DuckRange.merged(p.subtitles.map { ($0.start, $0.end) }))
        var title = TextClip.defaultStyle
        title.fontSize = 0.12
        title.verticalPosition = 0.45
        p.addText(TextClip(start: Time(seconds: 0.5), end: Time(seconds: 5), text: "我的周末", style: title, animation: .rise))
        var place = TextClip.defaultStyle
        place.fontSize = 0.045
        place.strokeWidth = 0
        place.backgroundColor = RGBA(r: 0, g: 0, b: 0, a: 0.45)
        place.horizontalPosition = 0.22
        place.verticalPosition = 0.88
        p.addText(TextClip(start: Time(seconds: 1), end: Time(seconds: 7), text: "📍 京都 · 岚山", style: place, animation: .rise))
        try ProjectFile.write(p, to: URL(fileURLWithPath: dir).appendingPathComponent("demo.framecut"))
    }
}

final class HDRDemoProjectMaker: XCTestCase {
    func testMakeHDRDemoProject() async throws {
        guard let dir = ProcessInfo.processInfo.environment["FC_DEMO_DIR"] else { throw XCTSkip("未设置 FC_DEMO_DIR") }
        var p = try await Fixtures.project(["hlg_bands_2s.mov", "landscape_10s.mp4", "pq_bands_2s.mov", "photo.jpg"])
        p.name = "HDR 演示"
        p.applyTransitionToAll(FCCore.Transition(kind: .dissolve, duration: Time(seconds: 0.5)))
        p.addSubtitle(at: Time(seconds: 0.2), text: "HDR 素材 + SDR 素材混剪", duration: Time(seconds: 10))
        try ProjectFile.write(p, to: URL(fileURLWithPath: dir).appendingPathComponent("hdr-demo.framecut"))
    }
}
