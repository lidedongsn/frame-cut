import Foundation
import FCCore
import simd

/// 滤镜预设 → 33³ 3D LUT（RGBA float，供 CIColorCubeWithColorSpace 使用）。强度已烘焙进 LUT。
enum FilterLUT {
    static let dimension = 33
    private static let lock = NSLock()
    private static var cache: [String: Data] = [:]

    static func data(preset: FilterPreset, intensity: Double) -> Data? {
        guard preset != .none, intensity > 0 else { return nil }
        let k = (min(1, intensity) * 20).rounded() / 20
        let key = "\(preset.rawValue)|\(k)"
        lock.lock()
        defer { lock.unlock() }
        if let hit = cache[key] { return hit }
        let n = dimension
        var values = [Float](repeating: 0, count: n * n * n * 4)
        var i = 0
        for b in 0..<n {
            for g in 0..<n {
                for r in 0..<n {
                    let input = SIMD3<Double>(Double(r), Double(g), Double(b)) / Double(n - 1)
                    let graded = grade(preset, input)
                    let out = simd_clamp(input + (graded - input) * k, .zero, .one)
                    values[i] = Float(out.x)
                    values[i + 1] = Float(out.y)
                    values[i + 2] = Float(out.z)
                    values[i + 3] = 1
                    i += 4
                }
            }
        }
        let data = values.withUnsafeBufferPointer { Data(buffer: $0) }
        cache[key] = data
        return data
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
