import AVFoundation
import FCCore
@testable import FCEngine
import FCMedia
import XCTest

/// 测试辅助：用测试素材建工程、取帧、读像素。
enum Fixtures {
    static func project(_ files: [String], aspect: AspectRatio = .r16x9) async throws -> Project {
        var p = Project(name: "test")
        p.aspect = aspect
        for f in files {
            let asset = try await MediaProbe.probe(url: TestMedia.url(f))
            if !p.assets.contains(where: { $0.path == asset.path }) { p.addAssets([asset]) }
            let id = p.assets.first { $0.path == asset.path }!.id
            p.appendToMain(assetID: id)
        }
        return p
    }

    static func frame(_ project: Project, at seconds: Double, shortSide: Int = 360) async throws -> CGImage {
        let size = RenderSize.size(aspect: project.aspect, shortSide: shortSide)
        let built = try await CompositionBuilder.build(project: project, renderSize: size)
        let gen = AVAssetImageGenerator(asset: built.composition)
        gen.videoComposition = built.makeVideoComposition(project: project, renderSize: size)
        gen.requestedTimeToleranceBefore = .zero
        gen.requestedTimeToleranceAfter = .zero
        return try await gen.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image
    }

    /// 返回 (r, g, b)，0...255；x、y 为相对坐标（左上为原点）。
    static func pixel(_ image: CGImage, x: Double, y: Double) -> (Int, Int, Int) {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let px = min(w - 1, Int(Double(w) * x)), py = min(h - 1, Int(Double(h) * y))
        let i = (py * w + px) * 4
        return (Int(data[i]), Int(data[i + 1]), Int(data[i + 2]))
    }

    static func meanLuma(_ image: CGImage) -> Double {
        var total = 0.0
        var n = 0.0
        for x in stride(from: 0.05, to: 1, by: 0.1) {
            for y in stride(from: 0.05, to: 1, by: 0.1) {
                let (r, g, b) = pixel(image, x: x, y: y)
                total += 0.299 * Double(r) + 0.587 * Double(g) + 0.114 * Double(b)
                n += 1
            }
        }
        return total / n
    }
}

final class CompositionTests: XCTestCase {
    func testRenderSize() {
        XCTAssertEqual(RenderSize.size(aspect: .r16x9, shortSide: 1080), CGSize(width: 1920, height: 1080))
        XCTAssertEqual(RenderSize.size(aspect: .r9x16, shortSide: 1080), CGSize(width: 1080, height: 1920))
        XCTAssertEqual(RenderSize.size(aspect: .r4x3, shortSide: 720), CGSize(width: 960, height: 720))
        XCTAssertEqual(RenderSize.size(aspect: .r1x1, shortSide: 2160), CGSize(width: 2160, height: 2160))
    }

    func testBuildDurations() async throws {
        var p = try await Fixtures.project(["landscape_10s.mp4", "landscape_10s.mp4"])
        p.transitions[p.mainTrack[1].id] = Transition(kind: .dissolve, duration: Time(seconds: 1))
        let built = try await CompositionBuilder.build(project: p, renderSize: CGSize(width: 640, height: 360))
        XCTAssertEqual(built.composition.duration.seconds, 19, accuracy: 0.05)
        XCTAssertEqual(built.duration.seconds, 19, accuracy: 0.05)
    }

    func testSpeedChangesDuration() async throws {
        var p = try await Fixtures.project(["landscape_10s.mp4"])
        p.setSpeed(id: p.mainTrack[0].id, 2)
        let built = try await CompositionBuilder.build(project: p, renderSize: CGSize(width: 640, height: 360))
        XCTAssertEqual(built.composition.duration.seconds, 5, accuracy: 0.05)
    }

    func testEmptyProjectThrows() async throws {
        do {
            _ = try await CompositionBuilder.build(project: Project(name: "e"), renderSize: CGSize(width: 640, height: 360))
            XCTFail("应抛 empty")
        } catch CompositionError.empty {}
    }

    func testRenderFrameNotBlank() async throws {
        let p = try await Fixtures.project(["landscape_10s.mp4"])
        let img = try await Fixtures.frame(p, at: 5)
        XCTAssertEqual(img.width, 640)
        XCTAssertEqual(img.height, 360)
        XCTAssertGreaterThan(Fixtures.meanLuma(img), 30)
    }

    func testImageClipRenders() async throws {
        let p = try await Fixtures.project(["photo.jpg"])
        let img = try await Fixtures.frame(p, at: 1)
        XCTAssertGreaterThan(Fixtures.meanLuma(img), 30)
    }

    func testRotatedVideoMatchesSystemOrientation() async throws {
        let url = try TestMedia.url("portrait_rotated_6s.mov")
        let reference = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        reference.appliesPreferredTrackTransform = true
        let ref = try await reference.image(at: CMTime(seconds: 1, preferredTimescale: 600)).image
        XCTAssertLessThan(ref.width, ref.height)

        let p = try await Fixtures.project(["portrait_rotated_6s.mov"], aspect: .r9x16)
        let img = try await Fixtures.frame(p, at: 1)
        for (x, y) in [(0.25, 0.5), (0.75, 0.5), (0.5, 0.25), (0.5, 0.75)] {
            let a = Fixtures.pixel(ref, x: x, y: y), b = Fixtures.pixel(img, x: x, y: y)
            XCTAssertEqual(a.0 > a.2, b.0 > b.2, "(\(x),\(y)) 参考 \(a) 渲染 \(b)")
        }
    }

    func testAllTransitionsRender() async throws {
        var p = try await Fixtures.project(["landscape_10s.mp4", "photo.jpg"])
        for kind in TransitionKind.allCases {
            p.transitions[p.mainTrack[1].id] = Transition(kind: kind, duration: Time(seconds: 1))
            // 转场区间 [9, 10)，取中点
            let img = try await Fixtures.frame(p, at: 9.5)
            XCTAssertEqual(img.width, 640, "\(kind)")
        }
    }

    func testFilterChangesPixels() async throws {
        var p = try await Fixtures.project(["landscape_10s.mp4"])
        let plain = try await Fixtures.frame(p, at: 3)
        p.updateMain(id: p.mainTrack[0].id) { $0.filter = FilterSettings(preset: .mono) }
        let mono = try await Fixtures.frame(p, at: 3)
        let (r, g, b) = Fixtures.pixel(mono, x: 0.3, y: 0.3)
        XCTAssertLessThan(abs(r - g) + abs(g - b), 12, "黑白滤镜后应接近灰色")
        XCTAssertNotEqual(Fixtures.meanLuma(plain), 0)
    }

    func testSubtitleOverlayChangesFrame() async throws {
        var p = try await Fixtures.project(["landscape_10s.mp4"])
        let before = try await Fixtures.frame(p, at: 2)
        p.addSubtitle(at: Time(seconds: 1), text: "字幕测试 Subtitle")
        let after = try await Fixtures.frame(p, at: 2)
        var differs = false
        for x in stride(from: 0.3, to: 0.7, by: 0.02) where Fixtures.pixel(before, x: x, y: 0.85) != Fixtures.pixel(after, x: x, y: 0.85) {
            differs = true
        }
        XCTAssertTrue(differs)
    }

    func testStructureKeyIgnoresVisualChanges() async throws {
        var p = try await Fixtures.project(["landscape_10s.mp4"])
        let k1 = CompositionBuilder.structureKey(p)
        p.updateMain(id: p.mainTrack[0].id) { $0.filter.preset = .warm; $0.volume = 0.3 }
        p.addSubtitle(at: .zero, text: "x")
        XCTAssertEqual(CompositionBuilder.structureKey(p), k1)
        p.setSpeed(id: p.mainTrack[0].id, 2)
        XCTAssertNotEqual(CompositionBuilder.structureKey(p), k1)
    }

    /// 切换 SDR / HDR 预览需要换合成器类，已有 AVPlayerItem 不能原地更新。
    func testColorModeSwitchNeedsNewPlayerItem() async throws {
        let p = try await Fixtures.project(["landscape_10s.mp4"])
        let built = try await CompositionBuilder.build(project: p, renderSize: CGSize(width: 640, height: 360))
        XCTAssertTrue(built.canUpdateInPlace(project: p, from: .sdr, to: .sdr))
        XCTAssertFalse(built.canUpdateInPlace(project: p, from: .sdr, to: .hlg))
        XCTAssertFalse(built.canUpdateInPlace(project: p, from: .hlg, to: .sdr))
        XCTAssertTrue(built.canUpdateInPlace(project: p, from: .hlg, to: .pq))
        var q = p
        q.setSpeed(id: q.mainTrack[0].id, 2)
        XCTAssertFalse(built.canUpdateInPlace(project: q, from: .sdr, to: .sdr))
    }
}
