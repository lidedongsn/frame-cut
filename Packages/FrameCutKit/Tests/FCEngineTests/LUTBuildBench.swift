import FCCore
@testable import FCEngine
import XCTest

/// 拖动调色滑块时每一步都要重建 LUT：全部调节 + HSL 下的耗时。
final class LUTBuildBench: XCTestCase {
    func testFullGradeLUTBuildTime() {
        var f = FilterSettings(preset: .film)
        f.shadows = 0.3; f.highlights = -0.2; f.vibrance = 0.2; f.tint = 0.1
        for band in HSLBand.allCases { f.hsl[band] = HSLAdjust(hue: 0.1, saturation: 0.1, luminance: 0.1) }
        var times: [Double] = []
        for i in 0..<10 {
            f.brightness = Double(i) * 0.05 - 0.2; f.hsl[.red] = HSLAdjust(hue: Double(i) * 0.03, saturation: 0.1, luminance: 0.1)
            let t = Date()
            XCTAssertNotNil(FilterLUT.data(f, space: .sdr))
            times.append(Date().timeIntervalSince(t) * 1000)
        }
        let avg = times.reduce(0, +) / Double(times.count)
        print("FCBENCH LUT build avg \(String(format: "%.1f", avg)) ms")
        XCTAssertLessThan(avg, 50, "单次 LUT 重建应在 50ms 内，拖动才流畅")
    }
}
