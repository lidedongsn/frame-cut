import Foundation

// MARK: - 文字与标题

/// 入场 / 出场动画。
public enum TextAnimation: String, Codable, CaseIterable, Sendable {
    case none, fade, rise, pop, typewriter

    public var displayName: String {
        switch self {
        case .none: String(localized: "无", bundle: .module)
        case .fade: String(localized: "淡入淡出", bundle: .module)
        case .rise: String(localized: "上浮", bundle: .module)
        case .pop: String(localized: "弹出", bundle: .module)
        case .typewriter: String(localized: "打字机", bundle: .module)
        }
    }
}

/// 独立的文字片段（标题、地点、日期、章节等）。与字幕不同，每段文字有自己的样式和位置。
public struct TextClip: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID = UUID()
    public var start: Time
    public var end: Time
    public var text: String
    /// 字体、颜色、描边、背景与位置，与字幕共用一套样式字段。
    public var style: SubtitleStyle
    public var animation: TextAnimation

    /// 文字字号可调范围（画布高度的比例），比字幕大。
    public static let fontSizeRange: ClosedRange<Double> = 0.02...0.25
    public static let defaultDuration = Time(seconds: 3)
    /// 入场 / 出场动画的时长（秒）；片段较短时按时长的三分之一。
    public static let animationSeconds = 0.4

    public init(id: UUID = UUID(), start: Time, end: Time, text: String, style: SubtitleStyle = TextClip.defaultStyle, animation: TextAnimation = .fade) {
        self.id = id
        self.start = start
        self.end = end
        self.text = text
        self.style = style
        self.animation = animation
    }

    /// 新文字的默认样式：画面正中，比字幕大一些。
    public static var defaultStyle: SubtitleStyle {
        var s = SubtitleStyle()
        s.fontSize = 0.07
        s.verticalPosition = 0.5
        s.strokeWidth = 0.08
        return s
    }

    public var duration: Time { end - start }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        start = try c.decode(Time.self, forKey: .start)
        end = try c.decode(Time.self, forKey: .end)
        text = try c.decode(String.self, forKey: .text)
        style = try c.decodeIfPresent(SubtitleStyle.self, forKey: .style) ?? TextClip.defaultStyle
        animation = try c.decodeIfPresent(TextAnimation.self, forKey: .animation) ?? .none
    }
}

/// 某一时刻文字的显示状态（由动画决定）。
public struct TextAppearance: Equatable, Sendable {
    public var opacity: Double = 1
    /// 竖直偏移，画布高度的比例，正值向下。
    public var offsetY: Double = 0
    /// 以文字中心缩放。
    public var scale: Double = 1
    /// 打字机效果显示的字符数；nil 为全部。
    public var visibleCharacters: Int?

    public init(opacity: Double = 1, offsetY: Double = 0, scale: Double = 1, visibleCharacters: Int? = nil) {
        self.opacity = opacity
        self.offsetY = offsetY
        self.scale = scale
        self.visibleCharacters = visibleCharacters
    }
}

extension TextClip {
    /// t 时刻的显示状态。入场取前 animationSeconds，出场取最后 animationSeconds 淡出（打字机、上浮、弹出都以淡出收尾）。
    public func appearance(at t: Time) -> TextAppearance {
        guard animation != .none else { return TextAppearance() }
        let length = max(0.001, duration.seconds)
        let d = min(TextClip.animationSeconds, length / 3)
        let elapsed = (t - start).seconds
        let remaining = (end - t).seconds
        let pin = min(1, max(0, elapsed / d))
        let pout = min(1, max(0, remaining / d))
        let easeIn = 1 - pow(1 - pin, 3)
        let fadeOut = 1 - pow(1 - pout, 3)
        switch animation {
        case .none:
            return TextAppearance()
        case .fade:
            return TextAppearance(opacity: min(easeIn, fadeOut))
        case .rise:
            return TextAppearance(opacity: min(easeIn, fadeOut), offsetY: (1 - easeIn) * 0.04)
        case .pop:
            // 回弹：略微超过原大小再回到 1
            let c1 = 1.70158, c3 = c1 + 1
            let back = 1 + c3 * pow(pin - 1, 3) + c1 * pow(pin - 1, 2)
            return TextAppearance(opacity: min(min(1, pin * 3), fadeOut), scale: 0.5 + 0.5 * back)
        case .typewriter:
            let count = text.trimmingCharacters(in: .whitespacesAndNewlines).count
            // 每字约 0.08 秒，最多占片段时长的 60%
            let typing = max(0.001, min(length * 0.6, Double(count) * 0.08))
            let shown = Int((Double(count) * min(1, max(0, elapsed / typing))).rounded(.up))
            return TextAppearance(opacity: fadeOut, visibleCharacters: min(count, shown))
        }
    }

    /// 时间线上的行号：按开始时间依次放进第一个空闲的行，重叠的文字放到下一行。
    public static func lanes(_ clips: [TextClip]) -> [UUID: Int] {
        var laneEnds: [Time] = []
        var result: [UUID: Int] = [:]
        for clip in clips.sorted(by: { ($0.start, $0.end) < ($1.start, $1.end) }) {
            if let i = laneEnds.firstIndex(where: { $0 <= clip.start }) {
                laneEnds[i] = clip.end
                result[clip.id] = i
            } else {
                laneEnds.append(clip.end)
                result[clip.id] = laneEnds.count - 1
            }
        }
        return result
    }

    public static func laneCount(_ clips: [TextClip]) -> Int {
        (lanes(clips).values.max() ?? -1) + 1
    }
}

// MARK: - 编辑

extension Project {
    public func text(id: UUID) -> TextClip? { texts.first { $0.id == id } }

    @discardableResult
    public mutating func addText(_ clip: TextClip) -> UUID {
        texts.append(clip)
        normalizeText(at: texts.count - 1)
        return clip.id
    }

    public mutating func updateText(id: UUID, _ body: (inout TextClip) -> Void) {
        guard let i = texts.firstIndex(where: { $0.id == id }) else { return }
        body(&texts[i])
        normalizeText(at: i)
    }

    public mutating func removeText(id: UUID) {
        texts.removeAll { $0.id == id }
    }

    /// 复制一份，接在原片段后面。返回副本 id。
    @discardableResult
    public mutating func duplicateText(id: UUID) -> UUID? {
        guard var copy = text(id: id) else { return nil }
        copy.id = UUID()
        let length = copy.duration
        copy.start = copy.end
        copy.end = copy.start + length
        return addText(copy)
    }

    private mutating func normalizeText(at i: Int) {
        texts[i].start = Time.max(.zero, texts[i].start)
        if texts[i].end - texts[i].start < EditLimits.minClipDuration {
            texts[i].end = texts[i].start + EditLimits.minClipDuration
        }
        texts.sort { $0.start < $1.start }
    }
}
