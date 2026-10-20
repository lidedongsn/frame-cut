import XCTest
@testable import FCCore

final class ColorGradingModelTests: XCTestCase {
    func testDefaultsAreIdentity() {
        let f = FilterSettings()
        XCTAssertTrue(f.isIdentity)
        XCTAssertTrue(f.colorIsIdentity)
        XCTAssertEqual(f.hsl.count, 0)
    }

    func testNewFieldsBreakIdentity() {
        var f = FilterSettings()
        f.shadows = 0.3
        XCTAssertFalse(f.colorIsIdentity)
        var g = FilterSettings()
        g.vignette = 0.5
        XCTAssertTrue(g.colorIsIdentity, "暗角是空间效果，不进颜色 LUT")
        XCTAssertFalse(g.isIdentity)
        var h = FilterSettings()
        h.hsl[.blue] = HSLAdjust(hue: 0, saturation: 0.4, luminance: 0)
        XCTAssertFalse(h.colorIsIdentity)
        var k = FilterSettings()
        k.hsl[.blue] = HSLAdjust()
        XCTAssertTrue(k.colorIsIdentity, "全 0 的 HSL 不算调节")
    }

    func testLUTSelectionReplacesPreset() {
        var f = FilterSettings(preset: .warm)
        f.selectLUT(UserLUTRef(id: UUID(), name: "Teal"))
        XCTAssertEqual(f.preset, .none)
        XCTAssertNotNil(f.lut)
        XCTAssertFalse(f.colorIsIdentity)
        f.selectPreset(.film)
        XCTAssertNil(f.lut)
        XCTAssertEqual(f.preset, .film)
    }

    func testLegacyFilterJSONDecodes() throws {
        let json = #"{"preset":"warm","intensity":0.8,"brightness":0.1,"contrast":0,"saturation":0,"temperature":0}"#
        let f = try JSONDecoder().decode(FilterSettings.self, from: Data(json.utf8))
        XCTAssertEqual(f.preset, .warm)
        XCTAssertEqual(f.intensity, 0.8)
        XCTAssertEqual(f.shadows, 0)
        XCTAssertNil(f.lut)
        XCTAssertTrue(f.hsl.isEmpty)
    }

    func testFilterRoundTrip() throws {
        var f = FilterSettings(preset: .film)
        f.highlights = -0.4; f.shadows = 0.3; f.vibrance = 0.2; f.tint = -0.1
        f.sharpen = 0.5; f.vignette = 0.3
        f.hsl[.orange] = HSLAdjust(hue: 0.1, saturation: -0.2, luminance: 0.3)
        f.lut = UserLUTRef(id: UUID(), name: "x")
        let d = try JSONDecoder().decode(FilterSettings.self, from: JSONEncoder().encode(f))
        XCTAssertEqual(d, f)
    }

    func testResetGroups() {
        var f = FilterSettings(preset: .film)
        f.brightness = 0.2; f.shadows = 0.3; f.sharpen = 0.4
        f.hsl[.red] = HSLAdjust(hue: 0.2, saturation: 0, luminance: 0)
        f.resetAdjustments()
        XCTAssertEqual(f.brightness, 0)
        XCTAssertEqual(f.shadows, 0)
        XCTAssertEqual(f.sharpen, 0)
        XCTAssertFalse(f.hsl.isEmpty, "基础调节重置不动 HSL")
        XCTAssertEqual(f.preset, .film)
        f.hsl = [:]
        XCTAssertTrue(f.hsl.isEmpty)
    }
}
