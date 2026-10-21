import AVFoundation
import FCCore
import Foundation

/// 输出动态范围：决定合成器输出格式、视频合成色彩属性与渲染目标色彩空间。
public enum DynamicRangeOutput: String, CaseIterable, Sendable {
    case sdr, hlg, pq

    public var isHDR: Bool { self != .sdr }

    public var displayName: String {
        switch self {
        case .sdr: "SDR"
        case .hlg: "HDR（HLG）"
        case .pq: "HDR10（PQ）"
        }
    }

    var colorSpace: CGColorSpace {
        switch self {
        case .sdr: CGColorSpace(name: CGColorSpace.itur_709)!
        case .hlg: CGColorSpace(name: CGColorSpace.itur_2100_HLG)!
        case .pq: CGColorSpace(name: CGColorSpace.itur_2100_PQ)!
        }
    }

    var colorProperties: [String: String] {
        [AVVideoColorPrimariesKey: colorPrimaries, AVVideoTransferFunctionKey: transferFunction, AVVideoYCbCrMatrixKey: yCbCrMatrix]
    }

    var colorPrimaries: String { isHDR ? AVVideoColorPrimaries_ITU_R_2020 : AVVideoColorPrimaries_ITU_R_709_2 }
    var yCbCrMatrix: String { isHDR ? AVVideoYCbCrMatrix_ITU_R_2020 : AVVideoYCbCrMatrix_ITU_R_709_2 }
    var transferFunction: String {
        switch self {
        case .sdr: AVVideoTransferFunction_ITU_R_709_2
        case .hlg: AVVideoTransferFunction_ITU_R_2100_HLG
        case .pq: AVVideoTransferFunction_SMPTE_ST_2084_PQ
        }
    }
}

enum LayerSource: Equatable {
    case track(CMPersistentTrackID)
    case image(URL)
}

/// 一个图层：来源 + 方向 + 用户变换 + 滤镜。
struct LayerSpec {
    var source: LayerSource
    /// 源帧存储尺寸（未旋转）。
    var naturalSize: CGSize
    /// 源轨道的 preferredTransform（图片为 identity，方向由 CIImage 读取 EXIF 处理）。
    var preferredTransform: CGAffineTransform
    var transform: ClipTransform
    var filter: FilterSettings
    /// 源为 HDR（HLG / PQ / 杜比视界）。
    var isHDR: Bool = false
}

/// 所有指令共享的场景信息（字幕等）。
final class RenderScene {
    let subtitles: [Subtitle]
    let style: SubtitleStyle

    init(subtitles: [Subtitle], style: SubtitleStyle) {
        self.subtitles = subtitles
        self.style = style
    }

    /// 当前显示的字幕，按开始时间排序（时间重叠的会上下排开显示）。
    func activeSubtitles(at t: Time) -> [Subtitle] {
        subtitles.filter { $0.start <= t && t < $0.end }.sorted { $0.start < $1.start }
    }
}

final class RenderInstruction: NSObject, AVVideoCompositionInstructionProtocol {
    let timeRange: CMTimeRange
    let enablePostProcessing = false
    let containsTweening = true
    let requiredSourceTrackIDs: [NSValue]?
    let passthroughTrackID = kCMPersistentTrackID_Invalid

    /// 从下到上：转场时 [前一片段, 后一片段]。
    let layers: [LayerSpec]
    let transition: (kind: TransitionKind, start: Time, duration: Time)?
    let scene: RenderScene
    let output: DynamicRangeOutput
    let colorMode: ColorMode

    init(timeRange: CMTimeRange, layers: [LayerSpec], transition: (kind: TransitionKind, start: Time, duration: Time)?,
         scene: RenderScene, trackIDs: [CMPersistentTrackID], output: DynamicRangeOutput = .sdr, colorMode: ColorMode = .sdr) {
        self.timeRange = timeRange
        self.output = output
        self.colorMode = colorMode
        self.layers = layers
        self.transition = transition
        self.scene = scene
        requiredSourceTrackIDs = trackIDs.map { NSNumber(value: $0) }
    }
}
