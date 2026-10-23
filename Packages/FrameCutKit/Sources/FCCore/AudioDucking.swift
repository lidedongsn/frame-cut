import Foundation

// MARK: - 人声避让

/// 人声区间（时间线时间）：开启避让的音频在这些区间内调低。可手动编辑，也可按字幕或声音生成。
public struct DuckRange: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID = UUID()
    public var start: Time
    public var end: Time

    public static let defaultDuration = Time(seconds: 2)

    public init(id: UUID = UUID(), start: Time, end: Time) {
        self.id = id
        self.start = start
        self.end = end
    }

    public var duration: Time { end - start }

    /// 把零散的时间段整理成区间：按时间排序，间隔小于 gap 的合并，短于 minLength 的丢掉。
    public static func merged(_ spans: [(Time, Time)], gap: Time = Time(seconds: 0.4), minLength: Time = Time(seconds: 0.2)) -> [DuckRange] {
        var result: [DuckRange] = []
        for (s, e) in spans.sorted(by: { $0.0 < $1.0 }) where e > s {
            if let last = result.last, s - last.end < gap {
                result[result.count - 1].end = Time.max(last.end, e)
            } else {
                result.append(DuckRange(start: s, end: e))
            }
        }
        return result.filter { $0.duration >= minLength }
    }
}

/// 避让参数（对所有开启避让的音频生效）。
public struct DuckSettings: Codable, Equatable, Sendable {
    /// 调低到原音量的比例。
    public var level = 0.3
    /// 进出区间的渐变时长（秒）。
    public var fade = 0.3

    public static let levelRange: ClosedRange<Double> = 0...1
    public static let fadeRange: ClosedRange<Double> = 0.05...1.5

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = DuckSettings()
        level = try c.decodeIfPresent(Double.self, forKey: .level) ?? d.level
        fade = try c.decodeIfPresent(Double.self, forKey: .fade) ?? d.fade
    }
}

/// 整条音频轨的设置。下标为轨号，随轨道收拢一起移动（见 arrangeAudioLanes）。
public struct AudioLaneSettings: Codable, Equatable, Sendable {
    public var muted = false
    public var volume = 1.0

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        muted = try c.decodeIfPresent(Bool.self, forKey: .muted) ?? false
        volume = try c.decodeIfPresent(Double.self, forKey: .volume) ?? 1
    }
}

/// 分段线性的音量包络（时间线时间）。
public struct VolumeEnvelope: Equatable, Sendable {
    public struct Point: Equatable, Sendable {
        public var time: Time
        public var gain: Double
    }

    public var points: [Point]

    public func gain(at t: Time) -> Double {
        guard let first = points.first, let last = points.last else { return 0 }
        if t <= first.time { return first.gain }
        if t >= last.time { return last.gain }
        guard let i = points.firstIndex(where: { $0.time > t }), i > 0 else { return last.gain }
        let a = points[i - 1], b = points[i]
        let span = (b.time - a.time).seconds
        guard span > 0 else { return b.gain }
        return a.gain + (b.gain - a.gain) * (t - a.time).seconds / span
    }
}

extension Project {
    // MARK: 区间编辑

    @discardableResult
    public mutating func addDuckRange(at t: Time, duration: Time = DuckRange.defaultDuration) -> UUID {
        let range = DuckRange(start: Time.max(.zero, t), end: Time.max(.zero, t) + duration)
        duckRanges.append(range)
        duckRanges.sort { $0.start < $1.start }
        return range.id
    }

    public mutating func updateDuckRange(id: UUID, _ body: (inout DuckRange) -> Void) {
        guard let i = duckRanges.firstIndex(where: { $0.id == id }) else { return }
        body(&duckRanges[i])
        duckRanges[i].start = Time.max(.zero, duckRanges[i].start)
        if duckRanges[i].duration < EditLimits.minClipDuration { duckRanges[i].end = duckRanges[i].start + EditLimits.minClipDuration }
        duckRanges.sort { $0.start < $1.start }
    }

    public mutating func removeDuckRange(id: UUID) {
        duckRanges.removeAll { $0.id == id }
    }

    public mutating func replaceDuckRanges(_ ranges: [DuckRange]) {
        duckRanges = ranges.sorted { $0.start < $1.start }
    }

    // MARK: 整条轨

    public func laneSettings(_ lane: Int) -> AudioLaneSettings {
        audioLanes.indices.contains(lane) ? audioLanes[lane] : AudioLaneSettings()
    }

    public mutating func updateAudioLane(_ lane: Int, _ body: (inout AudioLaneSettings) -> Void) {
        guard lane >= 0 else { return }
        while audioLanes.count <= lane { audioLanes.append(AudioLaneSettings()) }
        body(&audioLanes[lane])
        audioLanes[lane].volume = min(2, max(0, audioLanes[lane].volume))
    }

    // MARK: 音量包络

    /// 一段音频的音量包络：片段音量 × 轨道音量 × 淡入淡出 × 人声避让；片段或轨道静音时为 0。
    public func volumeEnvelope(for clip: AudioClip) -> VolumeEnvelope {
        let lane = laneSettings(clip.lane)
        let base = clip.muted || lane.muted ? 0 : clip.volume * lane.volume
        let fade = Time(seconds: duck.fade)
        let ranges = clip.ducks ? duckRanges.filter { $0.end + fade > clip.start && $0.start - fade < clip.end } : []

        func fadeGain(_ t: Time) -> Double {
            var g = 1.0
            if clip.fadeIn > .zero, t < clip.start + clip.fadeIn { g = min(g, (t - clip.start).seconds / clip.fadeIn.seconds) }
            if clip.fadeOut > .zero, t > clip.end - clip.fadeOut { g = min(g, (clip.end - t).seconds / clip.fadeOut.seconds) }
            return min(1, max(0, g))
        }
        func duckGain(_ t: Time) -> Double {
            var g = 1.0
            for r in ranges {
                let v: Double
                if t >= r.start, t <= r.end {
                    v = duck.level
                } else if t < r.start, t > r.start - fade {
                    v = 1 - (1 - duck.level) * (t - (r.start - fade)).seconds / fade.seconds
                } else if t > r.end, t < r.end + fade {
                    v = duck.level + (1 - duck.level) * (t - r.end).seconds / fade.seconds
                } else {
                    continue
                }
                g = min(g, v)
            }
            return g
        }

        var times: Set<Time> = [clip.start, clip.end, clip.start + clip.fadeIn, clip.end - clip.fadeOut]
        for r in ranges { times.formUnion([r.start - fade, r.start, r.end, r.end + fade]) }
        let points = times.filter { $0 >= clip.start && $0 <= clip.end }.sorted()
            .map { VolumeEnvelope.Point(time: $0, gain: base * fadeGain($0) * duckGain($0)) }
        return VolumeEnvelope(points: points)
    }
}

// MARK: - 按声音检测人声

/// 粗略的人声检测：按 20 毫秒分帧算响度，比环境底噪高出一截的部分算人声。
/// 风声、音乐等也会被当成人声，结果需要手动检查；有字幕时按字幕生成更准。
public enum SpeechDetector {
    public static func ranges(samples: [Float], sampleRate: Int) -> [DuckRange] {
        let frame = max(1, sampleRate / 50)
        guard samples.count >= frame else { return [] }
        var levels: [Double] = []
        levels.reserveCapacity(samples.count / frame)
        var i = 0
        while i + frame <= samples.count {
            var sum: Float = 0
            for j in i..<(i + frame) { sum += samples[j] * samples[j] }
            levels.append(20 * log10(Double(sqrt(sum / Float(frame))) + 1e-9))
            i += frame
        }
        guard let loudest = levels.max(), loudest > -50 else { return [] }
        let floor = levels.sorted()[levels.count / 10]
        let threshold = max(floor + 12, -45)
        let seconds = Double(frame) / Double(sampleRate)
        let pad = Time(seconds: 0.1)
        var spans: [(Time, Time)] = []
        var start: Int?
        for (k, level) in levels.enumerated() {
            if level >= threshold {
                if start == nil { start = k }
            } else if let s = start {
                spans.append((Time(seconds: Double(s) * seconds) - pad, Time(seconds: Double(k) * seconds) + pad))
                start = nil
            }
        }
        if let s = start { spans.append((Time(seconds: Double(s) * seconds) - pad, Time(seconds: Double(levels.count) * seconds))) }
        return DuckRange.merged(spans.map { (Time.max(.zero, $0.0), $0.1) }, minLength: Time(seconds: 0.4))
    }
}
