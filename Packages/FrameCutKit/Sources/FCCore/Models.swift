import Foundation

// MARK: - 工程

public enum AspectRatio: String, Codable, CaseIterable, Sendable {
    case r16x9, r9x16, r1x1, r4x3, r3x4

    /// 与素材宽高比最接近的画幅（按对数比较，横竖对称）。
    public static func nearest(width: Int, height: Int) -> AspectRatio {
        guard width > 0, height > 0 else { return .r16x9 }
        let r = log(Double(width) / Double(height))
        return allCases.min { abs(log($0.ratio) - r) < abs(log($1.ratio) - r) } ?? .r16x9
    }

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
    /// 为 true 时色彩模式跟随素材（有 HDR 素材即 HDR）；用户手动设置后为 false。
    public var colorModeIsAutomatic = true
    /// 为 true 时画幅与帧率跟随第一个导入的视频 / 图片；用户手动设置后为 false。
    public var formatIsAutomatic = true
    /// 为 true 时字幕跟随主轨：删除 / 修剪 / 变速 / 调序片段后，字幕跟着它下面的画面走。
    public var subtitlesFollowMain = true

    /// 工程可选帧率。
    public static let frameRates = [24, 25, 30, 50, 60]

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

/// HSL 分色调整的颜色区间。
public enum HSLBand: String, Codable, CaseIterable, Sendable, CodingKeyRepresentable {
    case red, orange, yellow, green, cyan, blue, purple, magenta

    public var displayName: String {
        switch self {
        case .red: "红"
        case .orange: "橙"
        case .yellow: "黄"
        case .green: "绿"
        case .cyan: "青"
        case .blue: "蓝"
        case .purple: "紫"
        case .magenta: "洋红"
        }
    }

    /// 区间中心色相（度）。
    public var hueCenter: Double {
        switch self {
        case .red: 0
        case .orange: 30
        case .yellow: 60
        case .green: 120
        case .cyan: 180
        case .blue: 225
        case .purple: 270
        case .magenta: 315
        }
    }
}

/// 一个颜色区间的调整，均为 -1...1。
public struct HSLAdjust: Codable, Equatable, Sendable {
    public var hue: Double = 0
    public var saturation: Double = 0
    public var luminance: Double = 0

    public init(hue: Double = 0, saturation: Double = 0, luminance: Double = 0) {
        self.hue = hue
        self.saturation = saturation
        self.luminance = luminance
    }

    public var isIdentity: Bool { hue == 0 && saturation == 0 && luminance == 0 }
}

/// 用户导入的 .cube LUT（文件存放在 App 的 LUT 库中）。
public struct UserLUTRef: Codable, Equatable, Hashable, Sendable {
    public var id: UUID
    public var name: String

    public init(id: UUID, name: String) {
        self.id = id
        self.name = name
    }
}

public struct FilterSettings: Codable, Equatable, Sendable {
    /// 风格：内置滤镜或用户 LUT（二选一），强度控制混合比例。
    public var preset: FilterPreset = .none
    public var lut: UserLUTRef?
    public var intensity: Double = 1
    /// 基础调节，均为 -1...1，0 表示不调节。
    public var brightness: Double = 0
    public var contrast: Double = 0
    public var highlights: Double = 0
    public var shadows: Double = 0
    public var saturation: Double = 0
    public var vibrance: Double = 0
    public var temperature: Double = 0
    /// 色调：正值偏洋红，负值偏绿。
    public var tint: Double = 0
    /// HSL 分色调整。
    public var hsl: [HSLBand: HSLAdjust] = [:]
    /// 效果（空间滤镜，不进颜色 LUT），0...1。
    public var sharpen: Double = 0
    public var vignette: Double = 0

    public init(preset: FilterPreset = .none) {
        self.preset = preset
    }

    public var hasLook: Bool { (preset != .none || lut != nil) && intensity > 0 }

    /// 颜色部分为恒等（不需要 LUT）。
    public var colorIsIdentity: Bool {
        !hasLook && brightness == 0 && contrast == 0 && highlights == 0 && shadows == 0 && saturation == 0
            && vibrance == 0 && temperature == 0 && tint == 0 && hsl.values.allSatisfy(\.isIdentity)
    }

    public var isIdentity: Bool { colorIsIdentity && sharpen == 0 && vignette == 0 }

    public mutating func selectPreset(_ p: FilterPreset) {
        preset = p
        lut = nil
        if intensity == 0 { intensity = 1 }
    }

    public mutating func selectLUT(_ ref: UserLUTRef) {
        lut = ref
        preset = .none
        if intensity == 0 { intensity = 1 }
    }

    /// 重置基础调节与效果（保留风格与 HSL）。
    public mutating func resetAdjustments() {
        brightness = 0; contrast = 0; highlights = 0; shadows = 0
        saturation = 0; vibrance = 0; temperature = 0; tint = 0
        sharpen = 0; vignette = 0
    }
}

extension FilterSettings {
    /// 旧工程只有部分字段，缺省的取默认值。
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func v(_ k: CodingKeys) throws -> Double { try c.decodeIfPresent(Double.self, forKey: k) ?? 0 }
        preset = try c.decodeIfPresent(FilterPreset.self, forKey: .preset) ?? .none
        lut = try c.decodeIfPresent(UserLUTRef.self, forKey: .lut)
        intensity = try c.decodeIfPresent(Double.self, forKey: .intensity) ?? 1
        brightness = try v(.brightness)
        contrast = try v(.contrast)
        highlights = try v(.highlights)
        shadows = try v(.shadows)
        saturation = try v(.saturation)
        vibrance = try v(.vibrance)
        temperature = try v(.temperature)
        tint = try v(.tint)
        hsl = try c.decodeIfPresent([HSLBand: HSLAdjust].self, forKey: .hsl) ?? [:]
        sharpen = try v(.sharpen)
        vignette = try v(.vignette)
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
    /// 字幕中心距画布左边的比例。
    public var horizontalPosition: Double = 0.5

    /// 字号可调范围（画布高度的比例）。
    public static let fontSizeRange: ClosedRange<Double> = 0.03...0.12

    public init() {}

    /// 字幕在画布上的位置（左上角为原点）：中心对准设定位置，超出画布时推回画内。预览与导出共用。
    public func frame(textSize: CGSize, canvas: CGSize) -> CGRect {
        let x = canvas.width * horizontalPosition - textSize.width / 2
        let y = canvas.height * verticalPosition - textSize.height / 2
        return CGRect(x: min(max(0, x), max(0, canvas.width - textSize.width)),
                      y: min(max(0, y), max(0, canvas.height - textSize.height)),
                      width: textSize.width, height: textSize.height)
    }
}

extension SubtitleStyle {
    // 旧工程没有新增字段，缺省时取默认值
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = SubtitleStyle()
        fontName = try c.decodeIfPresent(String.self, forKey: .fontName) ?? d.fontName
        fontSize = try c.decodeIfPresent(Double.self, forKey: .fontSize) ?? d.fontSize
        textColor = try c.decodeIfPresent(RGBA.self, forKey: .textColor) ?? d.textColor
        strokeColor = try c.decodeIfPresent(RGBA.self, forKey: .strokeColor) ?? d.strokeColor
        strokeWidth = try c.decodeIfPresent(Double.self, forKey: .strokeWidth) ?? d.strokeWidth
        backgroundColor = try c.decodeIfPresent(RGBA.self, forKey: .backgroundColor) ?? d.backgroundColor
        verticalPosition = try c.decodeIfPresent(Double.self, forKey: .verticalPosition) ?? d.verticalPosition
        horizontalPosition = try c.decodeIfPresent(Double.self, forKey: .horizontalPosition) ?? d.horizontalPosition
    }
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
        // 旧工程的画幅 / 帧率可能是手动设的
        formatIsAutomatic = try c.decodeIfPresent(Bool.self, forKey: .formatIsAutomatic) ?? false
        subtitlesFollowMain = try c.decodeIfPresent(Bool.self, forKey: .subtitlesFollowMain) ?? true
    }
}
