import XCTest
@testable import FCCore

final class ProjectFormatTests: XCTestCase {
    private func video(_ w: Int, _ h: Int, fps: Double = 30, hdr: HDRFormat? = nil) -> MediaAsset {
        MediaAsset(kind: .video, name: "v", path: "/v\(UUID())", duration: Time(seconds: 10), width: w, height: h,
                   hasAudio: true, frameRate: fps, hdr: hdr)
    }

    func testNearestAspect() {
        XCTAssertEqual(AspectRatio.nearest(width: 1920, height: 1080), .r16x9)
        XCTAssertEqual(AspectRatio.nearest(width: 1080, height: 1920), .r9x16)
        XCTAssertEqual(AspectRatio.nearest(width: 4032, height: 3024), .r4x3)
        XCTAssertEqual(AspectRatio.nearest(width: 3024, height: 4032), .r3x4)
        XCTAssertEqual(AspectRatio.nearest(width: 1080, height: 1080), .r1x1)
        XCTAssertEqual(AspectRatio.nearest(width: 2560, height: 1080), .r16x9)   // 21:9 → 最接近 16:9
    }

    func testNearestFrameRate() {
        XCTAssertEqual(Project.nearestFrameRate(23.976), 24)
        XCTAssertEqual(Project.nearestFrameRate(29.97), 30)
        XCTAssertEqual(Project.nearestFrameRate(25), 25)
        XCTAssertEqual(Project.nearestFrameRate(50), 50)
        XCTAssertEqual(Project.nearestFrameRate(59.94), 60)
        XCTAssertEqual(Project.nearestFrameRate(120), 60)   // 慢动作素材
        XCTAssertEqual(Project.nearestFrameRate(0), 30)
    }

    func testFirstImportSetsFormat() {
        var p = Project(name: "t")
        p.addAssets([video(1080, 1920, fps: 59.94)])
        XCTAssertEqual(p.aspect, .r9x16)
        XCTAssertEqual(p.frameRate, 60)
        // 之后导入的素材不再改变格式
        p.appendToMain(assetID: p.assets[0].id)
        p.addAssets([video(1920, 1080, fps: 24)])
        XCTAssertEqual(p.aspect, .r9x16)
        XCTAssertEqual(p.frameRate, 60)
    }

    func testImageSetsAspectButNotFrameRate() {
        var p = Project(name: "t")
        let img = MediaAsset(kind: .image, name: "i", path: "/i", duration: .zero, width: 3000, height: 3000, hasAudio: false, frameRate: 0)
        p.addAssets([img])
        XCTAssertEqual(p.aspect, .r1x1)
        XCTAssertEqual(p.frameRate, 30)
    }

    func testAudioDoesNotDecideFormat() {
        var p = Project(name: "t")
        let audio = MediaAsset(kind: .audio, name: "a", path: "/a", duration: Time(seconds: 5), width: 0, height: 0, hasAudio: true, frameRate: 0)
        p.addAssets([audio])
        XCTAssertTrue(p.formatIsAutomatic)
        p.addAssets([video(1080, 1920)])
        XCTAssertEqual(p.aspect, .r9x16)
    }

    func testManualFormatNotOverridden() {
        var p = Project(name: "t")
        p.setAspect(.r1x1)
        p.addAssets([video(1920, 1080, fps: 24)])
        XCTAssertEqual(p.aspect, .r1x1)
        XCTAssertEqual(p.frameRate, 30)
        XCTAssertFalse(p.formatIsAutomatic)
    }

    func testColorModeFollowsAssetsBothWays() {
        var p = Project(name: "t")
        p.addAssets([video(1920, 1080, hdr: .hlg)])
        XCTAssertEqual(p.colorMode, .hdr)
        p.removeAsset(id: p.assets[0].id)
        XCTAssertEqual(p.colorMode, .sdr, "删除全部 HDR 素材后自动回到 SDR")
    }

    func testRemoveAssetRemovesItsClips() {
        var p = Project(name: "t")
        p.addAssets([video(1920, 1080), video(1920, 1080)])
        p.appendToMain(assetID: p.assets[0].id)
        p.appendToMain(assetID: p.assets[1].id)
        p.removeAsset(id: p.assets[0].id)
        XCTAssertEqual(p.assets.count, 1)
        XCTAssertEqual(p.mainTrack.count, 1)
    }

    func testLegacyProjectFormatNotAutomatic() throws {
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Project(name: "t"))) as! [String: Any]
        json.removeValue(forKey: "formatIsAutomatic")
        let p = try JSONDecoder().decode(Project.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertFalse(p.formatIsAutomatic, "旧工程的比例 / 帧率可能是手动设的，不再自动改")
    }
}
