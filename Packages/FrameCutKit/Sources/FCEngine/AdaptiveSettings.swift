import FCCore
import Foundation

extension ExportSettings {
    /// 导出分辨率档位（短边）。
    public static let shortSides = [720, 1080, 2160]

    /// 按素材推荐导出设置：分辨率不超过视频素材（最低 720p），帧率同工程，HDR 工程导出 HLG。
    public static func recommended(for project: Project) -> ExportSettings {
        let videoShortSides = project.mainTrack.compactMap { clip -> Int? in
            guard let a = project.asset(id: clip.assetID), a.kind == .video else { return nil }
            return min(a.width, a.height)
        }
        let source = videoShortSides.max() ?? 1080
        let shortSide = shortSides.last { Double($0) <= Double(source) * 1.05 } ?? shortSides[0]
        return ExportSettings(shortSide: shortSide, frameRate: project.frameRate, codec: .h264,
                              dynamicRange: project.colorMode == .hdr ? .hlg : .sdr)
    }
}

/// 预览分辨率：跟随预览区实际像素，渲染跟不上时降档。
public enum PreviewQuality {
    public static let tiers = [360, 540, 720, 1080]

    /// 不小于预览区短边像素的最低档，且不超过 cap。
    public static func shortSide(viewPixels: Double, cap: Int) -> Int {
        let wanted = tiers.first { Double($0) >= viewPixels } ?? tiers.last!
        return min(wanted, cap)
    }

    /// 平均渲染耗时超过帧间隔的 80% 时，上限降一档。
    public static func capAfterMeasuring(cap: Int, averageRenderMs: Double, frameRate: Int) -> Int {
        let budget = 1000 / Double(max(1, frameRate)) * 0.8
        guard averageRenderMs > budget else { return cap }
        return tiers.last { $0 < cap } ?? tiers[0]
    }
}

/// 最近若干帧的渲染耗时（合成器线程写，主线程读）。
public final class RenderTimer: @unchecked Sendable {
    public static let preview = RenderTimer()

    private let lock = NSLock()
    private var samples: [Double] = []
    private let window = 30

    public init() {}

    public func record(ms: Double) {
        lock.withLock {
            samples.append(ms)
            if samples.count > window { samples.removeFirst(samples.count - window) }
        }
    }

    public var averageMs: Double? {
        lock.withLock { samples.isEmpty ? nil : samples.reduce(0, +) / Double(samples.count) }
    }

    public func reset() {
        lock.withLock { samples.removeAll() }
    }
}
