import Foundation

/// 主轨片段在时间线上的位置。
public struct ClipPlacement: Equatable, Sendable {
    public var clipID: UUID
    public var index: Int
    public var start: Time
    public var duration: Time
    /// A/B 轨：index % 2，相邻片段在不同轨，转场时可同时取帧。
    public var lane: Int
    /// 进入本片段的转场（已按相邻片段时长夹紧）；第一个片段恒为 nil。
    public var transitionIn: Transition?

    public var end: Time { start + duration }
    /// 转场区间（时间线时间）。
    public var transitionRange: (start: Time, end: Time)? {
        guard let t = transitionIn else { return nil }
        return (start, start + t.duration)
    }
}

/// 主轨布局：UI 与渲染引擎共用的纯计算。
public struct TimelineLayout: Equatable, Sendable {
    public private(set) var placements: [ClipPlacement] = []
    public private(set) var duration: Time = .zero

    public init(project: Project) {
        var cursor = Time.zero
        var previousDuration = Time.zero
        for (index, clip) in project.mainTrack.enumerated() {
            let duration = clip.timelineDuration
            var transition: Transition?
            if index > 0, var t = project.transitions[clip.id] {
                t.duration = TimelineLayout.clampedTransitionDuration(t.duration, previous: previousDuration, current: duration)
                if t.duration > .zero { transition = t }
            }
            let start = cursor - (transition?.duration ?? .zero)
            placements.append(ClipPlacement(clipID: clip.id, index: index, start: start, duration: duration,
                                            lane: index % 2, transitionIn: transition))
            cursor = start + duration
            previousDuration = duration
        }
        duration = cursor
    }

    public static func clampedTransitionDuration(_ d: Time, previous: Time, current: Time) -> Time {
        Time.max(.zero, Time.min(d, Time.min(previous / 2, current / 2)))
    }

    public func placement(for clipID: UUID) -> ClipPlacement? {
        placements.first { $0.clipID == clipID }
    }

    /// 最后一个 start <= t 且 t < end 的片段下标；越界返回 nil。
    public func clipIndex(at t: Time) -> Int? {
        guard t >= .zero, t < duration else { return nil }
        return placements.lastIndex { $0.start <= t }
    }
}
