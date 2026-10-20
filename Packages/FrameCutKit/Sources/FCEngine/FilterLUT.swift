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

/// 风格（内置滤镜或用户 LUT）+ 基础调节 + HSL → 一张 33³ 3D LUT（RGBA float）。锐化、暗角等空间效果不在这里。
enum FilterLUT {
    static let dimension = 33
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache = LRUCache<String, Data>(capacity: 64)

    private static func key(_ s: FilterSettings, _ space: GradingSpace) -> String {
        let hsl = HSLBand.allCases.compactMap { b in s.hsl[b].flatMap { $0.isIdentity ? nil : "\(b.rawValue):\($0.hue),\($0.saturation),\($0.luminance)" } }
        return "\(space.rawValue)|\(s.preset.rawValue)|\(s.lut?.id.uuidString ?? "")|\(s.intensity)|\(s.brightness)|\(s.contrast)|\(s.highlights)|\(s.shadows)"
            + "|\(s.saturation)|\(s.vibrance)|\(s.temperature)|\(s.tint)|\(hsl.joined(separator: ";"))"
    }

    private static func quantized(_ f: FilterSettings) -> FilterSettings {
        FilterSettings.quantized(f) { v, step in (v / step).rounded() * step }
    }

    static func purge() {
        lock.withLock { cache.removeAll() }
    }

    static func isCached(_ f: FilterSettings, space: GradingSpace) -> Bool {
        lock.withLock { cache.contains(key(quantized(f), space)) }
    }

    /// 锁只保护缓存读写；LUT 在锁外计算，渲染线程不会被正在拖动的滑块阻塞。
    static func data(_ f: FilterSettings, space: GradingSpace) -> Data? {
        var s = quantized(f)
        // 找不到的用户 LUT（被删除或在别的电脑上）按无风格处理
        let cube = s.lut.flatMap { UserLUTLibrary.shared.cube($0.id) }
        if cube == nil { s.lut = nil }
        guard !s.colorIsIdentity else { return nil }
        let key = key(s, space)
        if let hit = lock.withLock({ cache[key] }) { return hit }
        let data = build(s, space, cube)
        lock.withLock { cache[key] = data }
        return data
    }

    private static func build(_ s: FilterSettings, _ space: GradingSpace, _ cube: CubeLUT?) -> Data {
        let n = dimension
        let k = s.hasLook ? min(1, s.intensity) : 0
        var values = [Float](repeating: 0, count: n * n * n * 4)
        // 按蓝色切片并行计算（每片写不重叠的区间）
        let hsl = HSLTable(s.hsl)
        values.withUnsafeMutableBufferPointer { buf in
            let out = buf
            DispatchQueue.concurrentPerform(iterations: n) { b in
                var i = b * n * n * 4
                for g in 0..<n {
                    for r in 0..<n {
                        let input = SIMD3<Double>(Double(r), Double(g), Double(b)) / Double(n - 1)
                        let look = cube.map { $0.sample(input) } ?? grade(s.preset, input)
                        var o = input + (look - input) * k
                        o = adjust(o, s, space)
                        o = applyHSL(o, hsl)
                        o = simd_clamp(o, .zero, .one)
                        out[i] = Float(o.x)
                        out[i + 1] = Float(o.y)
                        out[i + 2] = Float(o.z)
                        out[i + 3] = 1
                        i += 4
                    }
                }
            }
        }
        return values.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    /// 调节参数（-1...1）作用于编码后的信号值。
    static func adjust(_ c: SIMD3<Double>, _ f: FilterSettings, _ space: GradingSpace) -> SIMD3<Double> {
        var o = c + SIMD3(repeating: f.brightness * 0.25)
        o = (o - 0.5) * (1 + f.contrast * 0.5) + 0.5
        // 高光 / 阴影：只影响各自亮度区间，纯黑纯白不动；按比例缩放 RGB 保持色相
        if f.highlights != 0 || f.shadows != 0 {
            let y = min(1, max(0, simd_dot(o, space.lumaWeights)))
            func bump(_ t: Double) -> Double { let t = min(1, max(0, t)); return 4 * t * (1 - t) }
            let target = y + f.shadows * 0.25 * bump(y / 0.7) + f.highlights * 0.25 * bump((y - 0.3) / 0.7)
            o = y > 1e-4 ? o * (target / y) : o + SIMD3(repeating: target - y)
        }
        let y = simd_dot(o, space.lumaWeights)
        o = SIMD3(repeating: y) + (o - SIMD3(repeating: y)) * max(0, 1 + f.saturation)
        // 自然饱和度：越不饱和的颜色提升越多，已经很艳的颜色基本不动
        if f.vibrance != 0 {
            let y = simd_dot(o, space.lumaWeights)
            let sat = min(1, max(0, o.max() - o.min()))
            o = SIMD3(repeating: y) + (o - SIMD3(repeating: y)) * max(0, 1 + f.vibrance * (1 - sat))
        }
        o *= SIMD3(1 + f.temperature * 0.12, 1, 1 - f.temperature * 0.12)
        o *= SIMD3(1 + f.tint * 0.05, 1 - f.tint * 0.08, 1 + f.tint * 0.05)
        return o
    }

    /// HSL 分色：按色相在相邻区间之间线性分配权重，灰色（低饱和）不受影响。
    static func applyHSL(_ c: SIMD3<Double>, _ hsl: [HSLBand: HSLAdjust]) -> SIMD3<Double> {
        applyHSL(c, HSLTable(hsl))
    }

    /// 预先展开的 HSL 参数：避免逐像素查字典。
    struct HSLTable {
        struct Entry {
            var center, left, right, hue, saturation, luminance: Double
        }

        let entries: [Entry]

        init(_ hsl: [HSLBand: HSLAdjust]) {
            let bands = HSLBand.allCases
            entries = bands.enumerated().compactMap { i, band in
                guard let adj = hsl[band], !adj.isIdentity else { return nil }
                let c0 = band.hueCenter
                let prev = bands[(i + bands.count - 1) % bands.count].hueCenter
                let next = bands[(i + 1) % bands.count].hueCenter
                return Entry(center: c0,
                             left: (c0 - prev + 360).truncatingRemainder(dividingBy: 360),
                             right: (next - c0 + 360).truncatingRemainder(dividingBy: 360),
                             hue: adj.hue, saturation: adj.saturation, luminance: adj.luminance)
            }
        }
    }

    static func applyHSL(_ c: SIMD3<Double>, _ table: HSLTable) -> SIMD3<Double> {
        guard !table.entries.isEmpty else { return c }
        let rgb = simd_clamp(c, .zero, .one)
        let mx = rgb.max(), mn = rgb.min(), d = mx - mn
        guard mx > 0, d > 1e-5 else { return c }
        var h: Double
        if mx == rgb.x { h = 60 * ((rgb.y - rgb.z) / d) } else if mx == rgb.y { h = 60 * ((rgb.z - rgb.x) / d + 2) } else { h = 60 * ((rgb.x - rgb.y) / d + 4) }
        if h < 0 { h += 360 }
        let s = d / mx
        let chroma = min(1, s / 0.2) // 接近灰色时逐渐减弱
        var hueShift = 0.0, satDelta = 0.0, lumDelta = 0.0
        for e in table.entries {
            var delta = h - e.center
            if delta > 180 { delta -= 360 }
            if delta < -180 { delta += 360 }
            let w = delta < 0 ? max(0, 1 + delta / e.left) : max(0, 1 - delta / e.right)
            guard w > 0 else { continue }
            hueShift += w * e.hue * 30
            satDelta += w * e.saturation
            lumDelta += w * e.luminance
        }
        // 1. 色相旋转（HSV，饱和度与明度不变）
        let h2 = (h + hueShift * chroma + 360).truncatingRemainder(dividingBy: 360)
        let v2 = mx, s2 = s
        let cc = v2 * s2
        let x = cc * (1 - abs((h2 / 60).truncatingRemainder(dividingBy: 2) - 1))
        let m = v2 - cc
        let (r, g, b): (Double, Double, Double)
        switch h2 {
        case ..<60: (r, g, b) = (cc, x, 0)
        case ..<120: (r, g, b) = (x, cc, 0)
        case ..<180: (r, g, b) = (0, cc, x)
        case ..<240: (r, g, b) = (0, x, cc)
        case ..<300: (r, g, b) = (x, 0, cc)
        default: (r, g, b) = (cc, 0, x)
        }
        var o = SIMD3(r + m, g + m, b + m)
        // 2. 饱和度：向亮度灰混合，去饱和时亮度不变
        let weights = SIMD3(0.2126, 0.7152, 0.0722)
        let y = simd_dot(o, weights)
        o = SIMD3(repeating: y) + (o - SIMD3(repeating: y)) * max(0, 1 + satDelta * chroma)
        // 3. 明亮度：整体缩放
        return o * (1 + lumDelta * 0.35 * chroma)
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
        s.highlights = q(f.highlights, 0.01)
        s.shadows = q(f.shadows, 0.01)
        s.vibrance = q(f.vibrance, 0.01)
        s.tint = q(f.tint, 0.01)
        s.hsl = f.hsl.mapValues { HSLAdjust(hue: q($0.hue, 0.01), saturation: q($0.saturation, 0.01), luminance: q($0.luminance, 0.01)) }
        return s
    }
}
