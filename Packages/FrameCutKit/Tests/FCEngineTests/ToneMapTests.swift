import CoreImage
import FCCore
@testable import FCEngine
import XCTest

/// 渲染单色 CIImage 到扩展线性空间并读回 R 通道。
func linearValue(_ image: CIImage) -> Float {
    var px = [Float](repeating: 0, count: 4)
    FrameRenderer.shared.context.render(image, toBitmap: &px, rowBytes: 16, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                                        format: .RGBAf, colorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!)
    return px[0]
}

func gray(_ v: Double) -> CIImage {
    CIImage(color: CIColor(red: v, green: v, blue: v, alpha: 1, colorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!)!)
        .cropped(to: CGRect(x: 0, y: 0, width: 4, height: 4))
}

final class ToneMapTests: XCTestCase {
    func testBelowKneeIdentity() {
        XCTAssertEqual(ToneMap.map(0.5), 0.5, accuracy: 1e-9)
        XCTAssertEqual(ToneMap.map(0.7), 0.7, accuracy: 1e-9)
    }

    func testReferenceWhite() {
        XCTAssertEqual(ToneMap.map(1.0), 0.86, accuracy: 0.02)
    }

    func testMonotonic() {
        var last = -1.0
        for x in stride(from: 0.0, through: 8.0, by: 0.01) {
            let y = ToneMap.map(x)
            XCTAssertGreaterThanOrEqual(y, last)
            last = y
        }
    }

    func testPeakMapsToOne() {
        XCTAssertEqual(ToneMap.map(ToneMap.peak), 1.0, accuracy: 1e-6)
        XCTAssertEqual(ToneMap.map(20), 1.0, accuracy: 1e-9)
    }

    func testHighlightsDistinct() {
        // 400 尼特与 1000 尼特映射后仍可区分
        XCTAssertGreaterThan(ToneMap.map(ToneMap.peak) - ToneMap.map(400.0 / 203.0), 0.03)
    }

    func testLUTKeepsMidtones() {
        XCTAssertEqual(linearValue(ToneMap.apply(gray(0.5))), 0.5, accuracy: 0.01)
    }

    /// CIColorCube 查表本身约有 1.5% 的系统误差（与维度、工作精度无关，已实测），容差按 4% 取。
    func testLUTCompressesPeak() {
        XCTAssertEqual(linearValue(ToneMap.apply(gray(1000.0 / 203.0))), 1.0, accuracy: 0.04)
        XCTAssertEqual(linearValue(ToneMap.apply(gray(1.0))), Float(ToneMap.map(1.0)), accuracy: 0.03)
        XCTAssertLessThan(linearValue(ToneMap.apply(gray(2.0))), linearValue(ToneMap.apply(gray(1000.0 / 203.0))))
    }

    func testHLGGradingPreservesHighlights() {
        var f = FilterSettings(preset: .film)
        f.contrast = 0.3
        let out = linearValue(FrameRenderer.filtered(gray(4.0), f, space: .hlg))
        XCTAssertGreaterThan(out, 2.0, "HDR 调色不应把高光压到 SDR 白以下")
    }

    func testSDRGradingAdjustmentsApplied() {
        var f = FilterSettings()
        f.brightness = 0.5
        XCTAssertGreaterThan(linearValue(FrameRenderer.filtered(gray(0.2), f, space: .sdr)), 0.25)
    }
}
