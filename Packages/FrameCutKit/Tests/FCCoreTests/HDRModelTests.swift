import XCTest
@testable import FCCore

final class HDRModelTests: XCTestCase {
    func testLegacyJSONDecodesWithDefaults() throws {
        // 不含 colorMode / hdr 字段的旧工程
        var legacy = makeProject(clipSeconds: [2])
        legacy.subtitles = []
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as! [String: Any]
        json.removeValue(forKey: "colorMode")
        json.removeValue(forKey: "colorModeIsAutomatic")
        var assets = json["assets"] as! [[String: Any]]
        assets[0].removeValue(forKey: "hdr")
        json["assets"] = assets
        let data = try JSONSerialization.data(withJSONObject: json)
        let p = try JSONDecoder().decode(Project.self, from: data)
        XCTAssertEqual(p.colorMode, .sdr)
        XCTAssertTrue(p.colorModeIsAutomatic)
        XCTAssertNil(p.assets[0].hdr)
        XCTAssertEqual(p.mainTrack, legacy.mainTrack)
    }

    func testImportHDRSwitchesColorMode() {
        var p = Project(name: "t")
        let sdr = MediaAsset(kind: .video, name: "s", path: "/s", duration: Time(seconds: 1), width: 1, height: 1, hasAudio: false, frameRate: 30)
        p.addAssets([sdr])
        XCTAssertEqual(p.colorMode, .sdr)
        var hdr = sdr
        hdr.id = UUID()
        hdr.hdr = .dolbyVision
        p.addAssets([hdr])
        XCTAssertEqual(p.colorMode, .hdr)
        XCTAssertTrue(p.hasHDRAssets)
    }

    func testManualColorModeNotOverridden() {
        var p = Project(name: "t")
        p.setColorMode(.sdr)
        XCTAssertFalse(p.colorModeIsAutomatic)
        var hdr = MediaAsset(kind: .video, name: "h", path: "/h", duration: Time(seconds: 1), width: 1, height: 1, hasAudio: false, frameRate: 30)
        hdr.hdr = .hlg
        p.addAssets([hdr])
        XCTAssertEqual(p.colorMode, .sdr)
    }

    func testAddAssetsSkipsDuplicates() {
        var p = Project(name: "t")
        let a = MediaAsset(kind: .video, name: "s", path: "/s", duration: Time(seconds: 1), width: 1, height: 1, hasAudio: false, frameRate: 30)
        p.addAssets([a, a])
        XCTAssertEqual(p.assets.count, 1)
    }

    /// 手写的 Project 解码必须覆盖所有字段：非默认值往返后应完全相等。
    func testProjectRoundTripKeepsEveryField() throws {
        var p = makeProject(clipSeconds: [2, 3])
        p.aspect = .r9x16
        p.frameRate = 60
        p.setColorMode(.hdr)
        p.subtitleStyle.verticalPosition = 0.3
        p.assets[0].hdr = .dolbyVisionPQ
        let decoded = try JSONDecoder().decode(Project.self, from: JSONEncoder().encode(p))
        XCTAssertEqual(decoded, p)
    }
}
