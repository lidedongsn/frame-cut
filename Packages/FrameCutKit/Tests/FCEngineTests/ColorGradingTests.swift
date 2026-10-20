import CoreImage
import FCCore
@testable import FCEngine
import simd
import XCTest

final class ColorGradingTests: XCTestCase {
    private func adjusted(_ c: SIMD3<Double>, _ change: (inout FilterSettings) -> Void) -> SIMD3<Double> {
        var f = FilterSettings()
        change(&f)
        return FilterLUT.adjust(c, f, .sdr)
    }

    private func gray(_ v: Double) -> SIMD3<Double> { SIMD3(repeating: v) }

    func testShadowsLiftDarksMoreThanBrights() {
        let dark = adjusted(gray(0.2)) { $0.shadows = 1 }.x - 0.2
        let bright = adjusted(gray(0.9)) { $0.shadows = 1 }.x - 0.9
        XCTAssertGreaterThan(dark, 0.05)
        XCTAssertLessThan(abs(bright), 0.02)
        XCTAssertEqual(adjusted(gray(0)) { $0.shadows = 1 }.x, 0, accuracy: 0.01, "纯黑保持黑")
    }

    func testHighlightsRecoverBrights() {
        let bright = adjusted(gray(0.85)) { $0.highlights = -1 }.x - 0.85
        let dark = adjusted(gray(0.15)) { $0.highlights = -1 }.x - 0.15
        XCTAssertLessThan(bright, -0.05)
        XCTAssertLessThan(abs(dark), 0.02)
    }

    func testVibranceBoostsMutedColorsMore() {
        let muted = SIMD3(0.5, 0.45, 0.4), vivid = SIMD3(0.9, 0.2, 0.1)
        func spread(_ c: SIMD3<Double>) -> Double { c.max() - c.min() }
        let gainMuted = spread(adjusted(muted) { $0.vibrance = 1 }) / spread(muted)
        let gainVivid = spread(adjusted(vivid) { $0.vibrance = 1 }) / spread(vivid)
        XCTAssertGreaterThan(gainMuted, gainVivid + 0.2)
    }

    func testTintPositiveIsMagenta() {
        let o = adjusted(gray(0.5)) { $0.tint = 1 }
        XCTAssertLessThan(o.y, 0.5)
        XCTAssertGreaterThan(o.x, o.y)
        XCTAssertGreaterThan(o.z, o.y)
    }

    func testHSLAffectsOnlyItsBand() {
        let blue = SIMD3(0.15, 0.3, 0.8), red = SIMD3(0.8, 0.15, 0.1), white = gray(0.7)
        var f = FilterSettings()
        f.hsl[.blue] = HSLAdjust(saturation: -1)
        let b = FilterLUT.applyHSL(blue, f.hsl)
        XCTAssertLessThan(b.max() - b.min(), 0.1, "蓝色去饱和后接近灰：\(b)")
        let w = SIMD3(0.2126, 0.7152, 0.0722)
        XCTAssertEqual(simd_dot(b, w), simd_dot(blue, w), accuracy: 0.03, "去饱和不应改变亮度")
        XCTAssertLessThan(simd_length(FilterLUT.applyHSL(red, f.hsl) - red), 0.01)
        XCTAssertLessThan(simd_length(FilterLUT.applyHSL(white, f.hsl) - white), 0.001, "灰色不受影响")
    }

    func testHSLHueShiftAndLuminance() {
        // 橙色（肤色）色相向黄偏
        let orange = SIMD3(0.9, 0.55, 0.3)
        let shifted = FilterLUT.applyHSL(orange, [.orange: HSLAdjust(hue: 1)])
        XCTAssertGreaterThan(shifted.y / shifted.x, orange.y / orange.x)
        let brighter = FilterLUT.applyHSL(orange, [.orange: HSLAdjust(luminance: 1)])
        XCTAssertGreaterThan(simd_dot(brighter, SIMD3(0.2126, 0.7152, 0.0722)), simd_dot(orange, SIMD3(0.2126, 0.7152, 0.0722)) + 0.03)
    }

    // MARK: .cube

    static let invertCube = """
    # 反色
    TITLE "Invert"
    LUT_3D_SIZE 2
    1 1 1
    0 1 1
    1 0 1
    0 0 1
    1 1 0
    0 1 0
    1 0 0
    0 0 0
    """

    func testParseCube() throws {
        let cube = try CubeLUT.parse(Self.invertCube)
        XCTAssertEqual(cube.size, 2)
        XCTAssertEqual(cube.title, "Invert")
        let o = cube.sample(SIMD3(0.25, 0.5, 1))
        XCTAssertEqual(o.x, 0.75, accuracy: 1e-6)
        XCTAssertEqual(o.y, 0.5, accuracy: 1e-6)
        XCTAssertEqual(o.z, 0, accuracy: 1e-6)
    }

    func testParseCubeDomain() throws {
        let text = "LUT_3D_SIZE 2\nDOMAIN_MIN 0 0 0\nDOMAIN_MAX 2 2 2\n" + Array(repeating: "0.5 0.5 0.5", count: 8).joined(separator: "\n")
        let cube = try CubeLUT.parse(text)
        XCTAssertEqual(cube.domainMax, SIMD3(repeating: 2))
    }

    func testParseCubeRejectsBadFiles() {
        XCTAssertThrowsError(try CubeLUT.parse("LUT_3D_SIZE 2\n0 0 0\n"))          // 数据不够
        XCTAssertThrowsError(try CubeLUT.parse("LUT_1D_SIZE 4\n0 0 0\n"))          // 1D LUT 不支持
        XCTAssertThrowsError(try CubeLUT.parse("hello"))
    }

    func testUserLUTAppliedByFilterLUT() throws {
        let id = UUID()
        UserLUTLibrary.shared.register(id: id, cube: try CubeLUT.parse(Self.invertCube))
        var f = FilterSettings()
        f.selectLUT(UserLUTRef(id: id, name: "Invert"))
        let data = try XCTUnwrap(FilterLUT.data(f, space: .sdr))
        let values = data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        XCTAssertEqual(values[0], 1, accuracy: 1e-4)   // 输入 (0,0,0) → (1,1,1)
        // 未注册的 LUT 视为无风格
        f.selectLUT(UserLUTRef(id: UUID(), name: "missing"))
        XCTAssertNil(FilterLUT.data(f, space: .sdr))
    }

    // MARK: 空间效果

    private func render(_ filter: FilterSettings) -> CIImage {
        let canvas = CGSize(width: 320, height: 180)
        let gray = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5)).cropped(to: CGRect(origin: .zero, size: canvas))
        return FrameRenderer.effects(gray, filter: filter, canvas: canvas)
    }

    private func value(_ image: CIImage, _ x: Double, _ y: Double) -> Float {
        var px = [Float](repeating: 0, count: 4)
        FrameRenderer.shared.context.render(image, toBitmap: &px, rowBytes: 16, bounds: CGRect(x: x, y: y, width: 1, height: 1),
                                            format: .RGBAf, colorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!)
        return px[0]
    }

    func testVignetteDarkensCorners() {
        var f = FilterSettings()
        f.vignette = 1
        let img = render(f)
        XCTAssertLessThan(value(img, 2, 2), value(img, 160, 90) * 0.7)
    }

    func testNoEffectsLeavesImageUntouched() {
        let img = render(FilterSettings())
        XCTAssertEqual(value(img, 2, 2), value(img, 160, 90), accuracy: 0.001)
    }
}
