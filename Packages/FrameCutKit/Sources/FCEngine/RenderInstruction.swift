import AVFoundation
import FCCore
import Foundation

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
}

/// 所有指令共享的场景信息（字幕等）。
final class RenderScene {
    let subtitles: [Subtitle]
    let style: SubtitleStyle

    init(subtitles: [Subtitle], style: SubtitleStyle) {
        self.subtitles = subtitles
        self.style = style
    }

    func activeSubtitles(at t: Time) -> [Subtitle] {
        subtitles.filter { $0.start <= t && t < $0.end }
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

    init(timeRange: CMTimeRange, layers: [LayerSpec], transition: (kind: TransitionKind, start: Time, duration: Time)?,
         scene: RenderScene, trackIDs: [CMPersistentTrackID]) {
        self.timeRange = timeRange
        self.layers = layers
        self.transition = transition
        self.scene = scene
        requiredSourceTrackIDs = trackIDs.map { NSNumber(value: $0) }
    }
}
