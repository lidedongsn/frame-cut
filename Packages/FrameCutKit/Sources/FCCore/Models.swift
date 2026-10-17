import Foundation

// MARK: - 工程

public enum AspectRatio: String, Codable, CaseIterable, Sendable {
    case r16x9, r9x16, r1x1, r4x3, r3x4

    /// 宽 / 高
    public var ratio: Double {
        switch self {
        case .r16x9: 16.0 / 9.0
        case .r9x16: 9.0 / 16.0
        case .r1x1: 1
        case .r4x3: 4.0 / 3.0
        case .r3x4: 3.0 / 4.0
        }
    }

    public var displayName: String {
        switch self {
        case .r16x9: "16:9"
        case .r9x16: "9:16"
        case .r1x1: "1:1"
        case .r4x3: "4:3"
        case .r3x4: "3:4"
        }
    }
}

/// 工程色彩模式。HDR 工程以 HDR 预览与导出（也可导出 SDR）。
public enum ColorMode: String, Codable, CaseIterable, Sendable {
    case sdr, hdr

    public var displayName: String { self == .sdr ? "SDR" : "HDR" }
}

public struct Project: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int = Project.currentSchemaVersion
    public var id: UUID = UUID()
    public var name: String
    public var aspect: AspectRatio = .r16x9
    public var frameRate: Int = 30
    public var assets: [MediaAsset] = []
    public var mainTrack: [VideoClip] = []
    /// 键：转场之后那个片段的 id（转场挂在它与前一片段的交界处）。
    public var transitions: [UUID: Transition] = [:]
    public var musicTrack: [AudioClip] = []
    public var subtitles: [Subtitle] = []
    public var subtitleStyle = SubtitleStyle()
    public var colorMode: ColorMode = .sdr
    /// 为 true 时导入 HDR 素材会自动切到 HDR；用户手动设置后为 false。
    public var colorModeIsAutomatic = true

    public init(name: String) {
        self.name = name
    }

    public func asset(id: UUID) -> MediaAsset? { assets.first { $0.id == id } }
    public func mainClip(id: UUID) -> VideoClip? { mainTrack.first { $0.id == id } }
    public func music(id: UUID) -> AudioClip? { musicTrack.first { $0.id == id } }
    public func subtitle(id: UUID) -> Subtitle? { subtitles.first { $0.id == id } }
}

// MARK: - 素材

public enum HDRFormat: String, Codable, Sendable {
    /// dolbyVision：底层 HLG（iPhone）；dolbyVisionPQ：底层 PQ。
    case hlg, pq, dolbyVision, dolbyVisionPQ

    public var displayName: String {
        switch self {
        case .hlg: "HLG"
        case .pq: "HDR10"
        case .dolbyVision, .dolbyVisionPQ: "杜比视界"
        }
    }

    /// 信号为 PQ 编码（否则为 HLG）。
    public var isPQ: Bool { self == .pq || self == .dolbyVisionPQ }
}

public enum MediaKind: String, Codable, Sendable {
    case video, image, audio
}

public struct MediaAsset: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID = UUID()
    public var kind: MediaKind
    public var name: String
    public var path: String
    public var bookmark: Data?
    /// 图片为 0，表示时长不受限。
    public var duration: Time
    /// 显示尺寸（已考虑旋转）。音频为 0。
    public var width: Int
    public var height: Int
    public var hasAudio: Bool
    public var frameRate: Double
    /// HDR 视频的格式；SDR 为 nil。
    public var hdr: HDRFormat?

    public init(id: UUID = UUID(), kind: MediaKind, name: String, path: String, bookmark: Data? = nil,
                duration: Time, width: Int, height: Int, hasAudio: Bool, frameRate: Double, hdr: HDRFormat? = nil) {
        self.hdr = hdr
        self.id = id
        self.kind = kind
        self.name = name
        self.path = path
        self.bookmark = bookmark
        self.duration = duration
        self.width = width
        self.height = height
        self.hasAudio = hasAudio
        self.frameRate = frameRate
    }

    public var url: URL { URL(fileURLWithPath: path) }
}

// MARK: - 主轨片段

public struct ClipTransform: Codable, Equatable, Sendable {
    /// 在“填充画幅”基础上的额外缩放。
    public var scale: Double = 1
    /// 位移，单位为画布宽 / 高的比例。
    public var offsetX: Double = 0
    public var offsetY: Double = 0
    /// 顺时针 90° 的次数。
    public var quarterTurns: Int = 0

    public init() {}
    public var isIdentity: Bool { self == ClipTransform() }
}

public enum FilterPreset: String, Codable, CaseIterable, Sendable {
    case none, fresh, warm, film, mono, vintage, cool, vivid, fade, cinematic

    public var displayName: String {
        switch self {
        case .none: "原画"
        case .fresh: "清新"
        case .warm: "暖阳"
        case .film: "胶片"
        case .mono: "黑白"
        case .vintage: "复古"
        case .cool: "冷调"
        case .vivid: "鲜艳"
        case .fade: "褪色"
        case .cinematic: "电影"
        }
    }
}

public struct FilterSettings: Codable, Equatable, Sendable {
    public var preset: FilterPreset = .none
    public var intensity: Double = 1
    /// 以下均为 -1...1，0 表示不调节。
    public var brightness: Double = 0
    public var contrast: Double = 0
    public var saturation: Double = 0
    public var temperature: Double = 0

    public init(preset: FilterPreset = .none) {
        self.preset = preset
    }

    public var isIdentity: Bool {
        (preset == .none || intensity == 0) && brightness == 0 && contrast == 0 && saturation == 0 && temperature == 0
    }
}

public struct VideoClip: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID = UUID()
    public var assetID: UUID
    public var sourceIn: Time
    public var sourceOut: Time
    public var speed: Double = 1
    public var volume: Double = 1
    public var muted: Bool = false
    public var transform = ClipTransform()
    public var filter = FilterSettings()

    public init(id: UUID = UUID(), assetID: UUID, sourceIn: Time, sourceOut: Time) {
        self.id = id
        self.assetID = assetID
        self.sourceIn = sourceIn
        self.sourceOut = sourceOut
    }

    public var sourceDuration: Time { sourceOut - sourceIn }
    public var timelineDuration: Time { sourceDuration / speed }
}

// MARK: - 转场

public enum TransitionKind: String, Codable, CaseIterable, Sendable {
    case dissolve, fadeBlack, fadeWhite, pushLeft, pushRight, pushUp, pushDown, slideLeft, wipeLeft, zoom, blur

    public var displayName: String {
        switch self {
        case .dissolve: "叠化"
        case .fadeBlack: "闪黑"
        case .fadeWhite: "闪白"
        case .pushLeft: "向左推"
        case .pushRight: "向右推"
        case .pushUp: "向上推"
        case .pushDown: "向下推"
        case .slideLeft: "滑入"
        case .wipeLeft: "擦除"
        case .zoom: "放大"
        case .blur: "模糊"
        }
    }
}

public struct Transition: Codable, Equatable, Sendable {
    public static let minDuration = Time(seconds: 0.2)
    public static let maxDuration = Time(seconds: 2)
    public static let defaultDuration = Time(seconds: 0.5)

    public var kind: TransitionKind
    public var duration: Time

    public init(kind: TransitionKind, duration: Time = Transition.defaultDuration) {
        self.kind = kind
        self.duration = duration.clamped(Transition.minDuration, Transition.maxDuration)
    }
}

// MARK: - 音乐

public struct AudioClip: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID = UUID()
    public var assetID: UUID
    public var start: Time
    public var sourceIn: Time
    public var sourceOut: Time
    public var volume: Double = 1
    public var fadeIn: Time = .zero
    public var fadeOut: Time = .zero

    public init(id: UUID = UUID(), assetID: UUID, start: Time, sourceIn: Time, sourceOut: Time) {
        self.id = id
        self.assetID = assetID
        self.start = start
        self.sourceIn = sourceIn
        self.sourceOut = sourceOut
    }

    public var duration: Time { sourceOut - sourceIn }
    public var end: Time { start + duration }
}

// MARK: - 字幕

public struct Subtitle: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID = UUID()
    public var start: Time
    public var end: Time
    public var text: String

    public init(id: UUID = UUID(), start: Time, end: Time, text: String) {
        self.id = id
        self.start = start
        self.end = end
        self.text = text
    }

    public var duration: Time { end - start }
}

public struct RGBA: Codable, Hashable, Sendable {
    public var r, g, b, a: Double

    public init(r: Double, g: Double, b: Double, a: Double = 1) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    public static let white = RGBA(r: 1, g: 1, b: 1)
    public static let black = RGBA(r: 0, g: 0, b: 0)
    public static let clear = RGBA(r: 0, g: 0, b: 0, a: 0)
}

public struct SubtitleStyle: Codable, Hashable, Sendable {
    public var fontName = "PingFangSC-Semibold"
    /// 字号，画布高度的比例。
    public var fontSize: Double = 0.055
    public var textColor = RGBA.white
    public var strokeColor = RGBA.black
    /// 描边宽度，字号的比例；0 为无描边。
    public var strokeWidth: Double = 0.12
    public var backgroundColor = RGBA.clear
    /// 字幕中心距画布顶部的比例。
    public var verticalPosition: Double = 0.85

    public init() {}
}

// MARK: - 兼容旧工程文件：新增字段缺省时取默认值
// MediaAsset 的新增字段都是可选类型，自动合成的解码已允许缺省；Project 的新增字段有默认值，需手写。

extension Project {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        aspect = try c.decode(AspectRatio.self, forKey: .aspect)
        frameRate = try c.decode(Int.self, forKey: .frameRate)
        assets = try c.decode([MediaAsset].self, forKey: .assets)
        mainTrack = try c.decode([VideoClip].self, forKey: .mainTrack)
        transitions = try c.decode([UUID: Transition].self, forKey: .transitions)
        musicTrack = try c.decode([AudioClip].self, forKey: .musicTrack)
        subtitles = try c.decode([Subtitle].self, forKey: .subtitles)
        subtitleStyle = try c.decode(SubtitleStyle.self, forKey: .subtitleStyle)
        colorMode = try c.decodeIfPresent(ColorMode.self, forKey: .colorMode) ?? .sdr
        colorModeIsAutomatic = try c.decodeIfPresent(Bool.self, forKey: .colorModeIsAutomatic) ?? true
    }
}
