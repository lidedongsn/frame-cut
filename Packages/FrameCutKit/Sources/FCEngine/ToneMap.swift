import CoreImage
import Foundation

/// HDR → SDR 色调映射。
///
/// 亮度以“相对参考白”的线性值表示（Core Image 约定 1.0 = 203 尼特，BT.2408）。
/// knee 以下保持不变；以上用有理函数平滑压缩，峰值 1000 尼特映射到 1.0，并保证在 knee 处斜率连续。
/// 逐通道映射：LUT 三线性插值精确、严格单调；极亮的饱和色会自然去饱和（与胶片 / ACES 类映射观感一致）。
enum ToneMap {
    static let knee = 0.7
    static let peak = 1000.0 / 203.0
    /// g(t) = t(1+a)/(t+a)，a 使 knee 处斜率为 1。
    private static let a: Double = {
        let slope = (peak - knee) / (1 - knee)
        return 1 / (slope - 1)
    }()

    static func map(_ x: Double) -> Double {
        guard x > knee else { return max(0, x) }
        guard x < peak else { return 1 }
        let t = (x - knee) / (peak - knee)
        return knee + (1 - knee) * (t * (1 + a) / (t + a))
    }

    static let dimension = 64 // CIColorCube 最大支持 64
    private static let pqSpace = CGColorSpace(name: CGColorSpace.itur_2100_PQ)!

    /// PQ 编码空间（覆盖 0–10000 尼特）中的 3D LUT（64³）。
    static let lut: Data = {
        let n = dimension
        var values = [Float](repeating: 0, count: n * n * n * 4)
        var i = 0
        for b in 0..<n {
            for g in 0..<n {
                for r in 0..<n {
                    for (k, c) in [r, g, b].enumerated() {
                        let x = PQ.decode(Double(c) / Double(n - 1)) / 203.0
                        values[i + k] = Float(PQ.encode(map(x) * 203.0))
                    }
                    values[i + 3] = 1
                    i += 4
                }
            }
        }
        return values.withUnsafeBufferPointer { Data(buffer: $0) }
    }()

    static func apply(_ image: CIImage) -> CIImage {
        image.applyingFilter("CIColorCubeWithColorSpace", parameters: [
            "inputCubeDimension": dimension,
            "inputCubeData": lut,
            "inputColorSpace": pqSpace,
        ])
    }
}

/// SMPTE ST 2084 (PQ)。
enum PQ {
    private static let m1 = 0.1593017578125, m2 = 78.84375
    private static let c1 = 0.8359375, c2 = 18.8515625, c3 = 18.6875

    static func encode(_ nits: Double) -> Double {
        let y = pow(max(0, nits) / 10000, m1)
        return pow((c1 + c2 * y) / (1 + c3 * y), m2)
    }

    static func decode(_ e: Double) -> Double {
        let p = pow(max(0, e), 1 / m2)
        return 10000 * pow(max(p - c1, 0) / (c2 - c3 * p), 1 / m1)
    }
}
