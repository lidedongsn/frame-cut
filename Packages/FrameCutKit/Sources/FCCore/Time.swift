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

    /// 形如 01:23.45 的显示文本。
    public var displayString: String {
        let total = Swift.max(0, seconds)
        let m = Int(total) / 60
        let s = total - Double(m * 60)
        return String(format: "%02d:%05.2f", m, s)
    }
}
