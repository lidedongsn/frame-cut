import CoreGraphics
import FCCore
import Foundation
import simd

/// 调色空间：SDR 工程在 sRGB 中调色；HDR 工程在 HLG 中调色（覆盖到 1000 尼特，不截断高光）。
enum GradingSpace: String, Sendable {
    case sdr, hlg

    var colorSpace: CGColorSpace {
        CGColorSpace(name: self == .sdr ? CGColorSpace.sRGB : CGColorSpace.itur_2100_HLG)!
    }

    /// 亮度权重：sRGB 用 BT.709，HLG 用 BT.2020。
    var lumaWeights: SIMD3<Double> {
        self == .sdr ? SIMD3(0.2126, 0.7152, 0.0722) : SIMD3(0.2627, 0.6780, 0.0593)
    }
}

/// 滤镜预设 + 调节（亮度、对比度、饱和度、色温）→ 一张 33³ 3D LUT（RGBA float）。
enum FilterLUT {
    static let dimension = 33
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache = LRUCache<String, Data>(capacity: 64)

    private static func key(_ s: FilterSettings, _ space: GradingSpace) -> String {
        "\(space.rawValue)|\(s.preset.rawValue)|\(s.intensity)|\(s.brightness)|\(s.contrast)|\(s.saturation)|\(s.temperature)"
    }

    private static func quantized(_ f: FilterSettings) -> FilterSettings {
        FilterSettings.quantized(f) { v, step in (v / step).rounded() * step }
    }

    static func isCached(_ f: FilterSettings, space: GradingSpace) -> Bool {
        lock.withLock { cache.contains(key(quantized(f), space)) }
    }

    /// 锁只保护缓存读写；LUT 在锁外计算，渲染线程不会被正在拖动的滑块阻塞。
    static func data(_ f: FilterSettings, space: GradingSpace) -> Data? {
        guard !f.isIdentity else { return nil }
        let s = quantized(f)
        let key = key(s, space)
        if let hit = lock.withLock({ cache[key] }) { return hit }
        let data = build(s, space)
        lock.withLock { cache[key] = data }
        return data
    }

    private static func build(_ s: FilterSettings, _ space: GradingSpace) -> Data {
        let n = dimension
        let k = s.preset == .none ? 0 : min(1, s.intensity)
        var values = [Float](repeating: 0, count: n * n * n * 4)
        var i = 0
        for b in 0..<n {
            for g in 0..<n {
                for r in 0..<n {
                    let input = SIMD3<Double>(Double(r), Double(g), Double(b)) / Double(n - 1)
                    var out = input + (grade(s.preset, input) - input) * k
                    out = adjust(out, s, space)
                    out = simd_clamp(out, .zero, .one)
                    values[i] = Float(out.x)
                    values[i + 1] = Float(out.y)
                    values[i + 2] = Float(out.z)
                    values[i + 3] = 1
                    i += 4
                }
            }
        }
        return values.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    /// 调节参数（-1...1）作用于编码后的信号值。
    static func adjust(_ c: SIMD3<Double>, _ f: FilterSettings, _ space: GradingSpace) -> SIMD3<Double> {
        var o = c + SIMD3(repeating: f.brightness * 0.25)
        o = (o - 0.5) * (1 + f.contrast * 0.5) + 0.5
        let y = simd_dot(o, space.lumaWeights)
        o = SIMD3(repeating: y) + (o - SIMD3(repeating: y)) * max(0, 1 + f.saturation)
        o *= SIMD3(1 + f.temperature * 0.12, 1, 1 - f.temperature * 0.12)
        return o
    }

    // MARK: 调色函数（输入输出均为 0...1 的 sRGB）

    static func grade(_ preset: FilterPreset, _ c: SIMD3<Double>) -> SIMD3<Double> {
        switch preset {
        case .none:
            return c
        case .fresh:
            var o = saturate(c, 1.12)
            o = o * SIMD3(0.98, 1.03, 1.04) + SIMD3(0.01, 0.02, 0.03)
            return lift(o, 0.03)
        case .warm:
            return saturate(c * SIMD3(1.08, 1.02, 0.88) + SIMD3(0.03, 0.01, 0), 1.05)
        case .film:
            var o = sCurve(c, 0.35)
            o = saturate(o, 0.85)
            o = lift(o, 0.05)
            return o * SIMD3(1.04, 1.0, 0.94)
        case .mono:
            let y = luma(c)
            return sCurve(SIMD3(repeating: y), 0.2)
        case .vintage:
            let y = luma(c)
            let sepia = SIMD3(y * 1.07 + 0.05, y * 0.95 + 0.02, y * 0.75)
            let o = c * 0.45 + sepia * 0.55
            return lift(o, 0.08) * 0.96
        case .cool:
            return c * SIMD3(0.9, 1.0, 1.08) + SIMD3(0, 0.01, 0.03)
        case .vivid:
            return sCurve(saturate(c, 1.4), 0.15)
        case .fade:
            return saturate(lift(c, 0.12) * 0.92, 0.75)
        case .cinematic:
            let y = luma(c)
            let shadowTint = SIMD3<Double>(-0.04, 0.02, 0.06) * (1 - y)
            let highlightTint = SIMD3<Double>(0.06, 0.02, -0.05) * y
            return sCurve(saturate(c + shadowTint + highlightTint, 0.9), 0.25)
        }
    }

    private static func luma(_ c: SIMD3<Double>) -> Double { 0.2126 * c.x + 0.7152 * c.y + 0.0722 * c.z }

    private static func saturate(_ c: SIMD3<Double>, _ amount: Double) -> SIMD3<Double> {
        let y = luma(c)
        return SIMD3(repeating: y) + (c - SIMD3(repeating: y)) * amount
    }

    /// 抬黑位。
    private static func lift(_ c: SIMD3<Double>, _ amount: Double) -> SIMD3<Double> {
        c * (1 - amount) + SIMD3(repeating: amount)
    }

    /// S 曲线加对比度，strength 0...1。
    private static func sCurve(_ c: SIMD3<Double>, _ strength: Double) -> SIMD3<Double> {
        func f(_ x: Double) -> Double {
            let x = min(max(x, 0), 1)
            let s = x * x * (3 - 2 * x)
            return x + (s - x) * strength
        }
        return SIMD3(f(c.x), f(c.y), f(c.z))
    }
}

extension FilterSettings {
    /// 量化参数以提高 LUT 缓存命中（强度 0.05，调节 0.01）。
    static func quantized(_ f: FilterSettings, _ q: (Double, Double) -> Double) -> FilterSettings {
        var s = f
        s.intensity = q(f.intensity, 0.05)
        s.brightness = q(f.brightness, 0.01)
        s.contrast = q(f.contrast, 0.01)
        s.saturation = q(f.saturation, 0.01)
        s.temperature = q(f.temperature, 0.01)
        return s
    }
}
