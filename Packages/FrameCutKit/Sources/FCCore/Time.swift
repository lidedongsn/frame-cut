import CoreMedia
import Foundation

/// 时间线时间，整数微秒，避免浮点累积误差。
public struct Time: Codable, Hashable, Comparable, AdditiveArithmetic, Sendable {
    public static let timescale: Int32 = 1_000_000

    public var microseconds: Int64

    public init(microseconds: Int64) {
        self.microseconds = microseconds
    }

    public init(seconds: Double) {
        microseconds = Int64((seconds * Double(Time.timescale)).rounded())
    }

    public init(_ cmTime: CMTime) {
        guard cmTime.isNumeric else {
            microseconds = 0
            return
        }
        microseconds = cmTime.convertScale(Time.timescale, method: .roundHalfAwayFromZero).value
    }

    public var seconds: Double { Double(microseconds) / Double(Time.timescale) }
    public var cmTime: CMTime { CMTime(value: microseconds, timescale: Time.timescale) }

    public static let zero = Time(microseconds: 0)

    public static func + (lhs: Time, rhs: Time) -> Time { Time(microseconds: lhs.microseconds + rhs.microseconds) }
    public static func - (lhs: Time, rhs: Time) -> Time { Time(microseconds: lhs.microseconds - rhs.microseconds) }
    public static func * (lhs: Time, rhs: Double) -> Time { Time(microseconds: Int64((Double(lhs.microseconds) * rhs).rounded())) }
    public static func / (lhs: Time, rhs: Double) -> Time { Time(microseconds: Int64((Double(lhs.microseconds) / rhs).rounded())) }
    public static func < (lhs: Time, rhs: Time) -> Bool { lhs.microseconds < rhs.microseconds }

    public static func min(_ a: Time, _ b: Time) -> Time { a < b ? a : b }
    public static func max(_ a: Time, _ b: Time) -> Time { a < b ? b : a }

    public func clamped(_ lower: Time, _ upper: Time) -> Time { Time.max(lower, Time.min(upper, self)) }

    /// 时:分:秒.百分秒，如 00:01:05.30。先取整到百分秒再拆分，不会出现 60 秒。
    public var displayString: String {
        let cs = Int((Swift.max(0, seconds) * 100).rounded())
        return String(format: "%02d:%02d:%02d.%02d", cs / 360_000, cs / 6000 % 60, cs / 100 % 60, cs % 100)
    }

    /// 时间线刻度：主刻度为整秒时显示 时:分:秒，否则带小数（0.25 秒这类刻度带两位）。
    public static func rulerLabel(seconds: Double, major: Double) -> String {
        if major >= 1 {
            let s = Int(Swift.max(0, seconds).rounded())
            return String(format: "%02d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
        }
        if (major * 10).rounded() != major * 10 {
            return Time(seconds: seconds).displayString
        }
        let ds = Int((Swift.max(0, seconds) * 10).rounded())
        return String(format: "%02d:%02d:%02d.%d", ds / 36000, ds / 600 % 60, ds / 10 % 60, ds % 10)
    }
}
