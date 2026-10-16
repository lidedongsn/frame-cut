import Foundation

/// 时间线缩放：范围限制、滚轮换算、保持锚点（鼠标处或播放头）在屏幕上不动。
public enum TimelineZoom {
    public static let minPointsPerSecond = 8.0
    public static let maxPointsPerSecond = 600.0

    public static func clamped(_ pps: Double) -> Double {
        min(maxPointsPerSecond, max(minPointsPerSecond, pps))
    }

    /// 滚轮增量 → 缩放倍数（指数形式，正负对称）。
    public static func factor(scrollDelta: Double) -> Double {
        exp(scrollDelta * 0.03)
    }

    /// 缩放后新的横向滚动原点，使 anchor 时刻保持在原来的屏幕位置；不小于 0。
    public static func scrollOrigin(anchor: Time, oldPointsPerSecond: Double, newPointsPerSecond: Double,
                                    oldOrigin: Double, leading: Double) -> Double {
        let screenX = leading + anchor.seconds * oldPointsPerSecond - oldOrigin
        return max(0, leading + anchor.seconds * newPointsPerSecond - screenX)
    }
}
