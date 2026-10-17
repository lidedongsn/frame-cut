import Foundation

/// 时间线缩放：范围限制、滚轮换算、保持锚点（鼠标处或播放头）在屏幕上不动。
public enum TimelineZoom {
    /// 最小 0.5pt/秒：20 分钟视频约 600pt，能整段放进时间线。
    public static let minPointsPerSecond = 0.5
    /// 最大 1200pt/秒：30fps 下每帧 40pt，可逐帧对齐。
    public static let maxPointsPerSecond = 1200.0

    public static func clamped(_ pps: Double) -> Double {
        min(maxPointsPerSecond, max(minPointsPerSecond, pps))
    }

    /// 适应窗口：整段时长铺满可视宽度；空工程回到默认 60pt/秒。
    public static func fit(duration: Time, viewportWidth: Double, leading: Double, trailing: Double) -> Double {
        guard duration.seconds > 0 else { return 60 }
        return clamped((viewportWidth - leading - trailing) / duration.seconds)
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
