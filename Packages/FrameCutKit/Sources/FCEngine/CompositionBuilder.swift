import AVFoundation
import FCCore
import Foundation

public enum CompositionError: LocalizedError {
    case empty
    case missingAsset(String)

    public var errorDescription: String? {
        switch self {
        case .empty: "时间线上还没有视频或图片"
        case .missingAsset(let name): "找不到素材：\(name)"
        }
    }
}

/// 构建结果。结构（轨道与时间）固定；视觉参数与音量可通过 make* 方法随时重建，无需重建合成。
public final class BuiltComposition: @unchecked Sendable {
    public let composition: AVMutableComposition
    public let duration: Time
    public let structureKey: CompositionBuilder.StructureKey

    struct VideoSource {
        var trackID: CMPersistentTrackID
        var naturalSize: CGSize
        var preferredTransform: CGAffineTransform
    }

    let baseTrackID: CMPersistentTrackID
    let videoSources: [UUID: VideoSource]
    let laneAudioTracks: [AVMutableCompositionTrack?]
    let clipHasAudio: Set<UUID>
    let musicTracks: [UUID: AVMutableCompositionTrack]

    init(composition: AVMutableComposition, duration: Time, structureKey: CompositionBuilder.StructureKey,
         baseTrackID: CMPersistentTrackID, videoSources: [UUID: VideoSource], laneAudioTracks: [AVMutableCompositionTrack?],
         clipHasAudio: Set<UUID>, musicTracks: [UUID: AVMutableCompositionTrack]) {
        self.composition = composition
        self.duration = duration
        self.structureKey = structureKey
        self.baseTrackID = baseTrackID
        self.videoSources = videoSources
        self.laneAudioTracks = laneAudioTracks
        self.clipHasAudio = clipHasAudio
        self.musicTracks = musicTracks
    }

    /// 已有播放项能否只替换视频指令与混音：结构未变，且输出 SDR / HDR 不变（合成器类在播放项创建后无法更换）。
    public func canUpdateInPlace(project: Project, from current: DynamicRangeOutput, to next: DynamicRangeOutput) -> Bool {
        current.isHDR == next.isHDR && structureKey == CompositionBuilder.structureKey(project)
    }

    // MARK: 视频合成指令

    public func makeVideoComposition(project: Project, renderSize: CGSize, output: DynamicRangeOutput = .sdr) -> AVMutableVideoComposition {
        let layout = TimelineLayout(project: project)
        let scene = RenderScene(subtitles: project.subtitles, style: project.subtitleStyle, texts: project.texts)
        let total = Time.max(Time(composition.duration), layout.duration)

        var bounds = Set<Time>([.zero, total])
        for p in layout.placements {
            bounds.insert(p.start)
            bounds.insert(p.end)
            if let r = p.transitionRange { bounds.insert(r.end) }
        }
        let sorted = bounds.filter { $0 <= total }.sorted()

        var instructions: [RenderInstruction] = []
        for (a, b) in zip(sorted, sorted.dropFirst()) where b > a {
            let mid = a + (b - a) / 2
            let active = layout.placements.filter { $0.start <= mid && mid < $0.end }
            var layers: [LayerSpec] = []
            var trackIDs: [CMPersistentTrackID] = [baseTrackID]
            for placement in active {
                guard let clip = project.mainClip(id: placement.clipID), let asset = project.asset(id: clip.assetID) else { continue }
                if asset.kind == .image {
                    layers.append(LayerSpec(source: .image(asset.url), naturalSize: CGSize(width: asset.width, height: asset.height),
                                            preferredTransform: .identity, transform: clip.transform, filter: clip.filter, isHDR: false))
                } else if let src = videoSources[clip.id] {
                    layers.append(LayerSpec(source: .track(src.trackID), naturalSize: src.naturalSize,
                                            preferredTransform: src.preferredTransform, transform: clip.transform, filter: clip.filter,
                                            isHDR: asset.hdr != nil))
                    trackIDs.append(src.trackID)
                }
            }
            var transition: (kind: TransitionKind, start: Time, duration: Time)?
            if active.count == 2, let t = active[1].transitionIn {
                transition = (t.kind, active[1].start, t.duration)
            }
            let range = CMTimeRange(start: a.cmTime, end: b.cmTime)
            instructions.append(RenderInstruction(timeRange: range, layers: layers, transition: transition, scene: scene, trackIDs: trackIDs,
                                                  output: output, colorMode: project.colorMode))
        }

        let vc = AVMutableVideoComposition()
        // 不设置 vc 的色彩属性：设置后 AVFoundation 会把源帧改标为目标色彩空间却不转换数值（如 HLG 被当作 PQ）。
        // 源帧保留原始标记，由合成器统一做色彩转换，并在输出缓冲上标记目标色彩空间。
        vc.customVideoCompositorClass = output.isHDR ? HDRCompositor.self : SDRCompositor.self
        vc.renderSize = renderSize
        vc.frameDuration = CMTime(value: 1, timescale: CMTimeScale(max(1, project.frameRate)))
        vc.instructions = instructions
        return vc
    }

    // MARK: 混音

    public func makeAudioMix(project: Project) -> AVMutableAudioMix {
        let layout = TimelineLayout(project: project)
        var params: [AVMutableAudioMixInputParameters] = []

        for lane in 0..<2 {
            guard let track = laneAudioTracks[lane] else { continue }
            let p = AVMutableAudioMixInputParameters(track: track)
            p.setVolume(0, at: .zero)
            let placements = layout.placements.filter { $0.lane == lane }
            for placement in placements {
                guard let clip = project.mainClip(id: placement.clipID) else { continue }
                let v = Float(clipHasAudio.contains(clip.id) && !clip.muted ? clip.volume : 0)
                if let r = placement.transitionRange {
                    p.setVolumeRamp(fromStartVolume: 0, toEndVolume: v, timeRange: CMTimeRange(start: r.start.cmTime, end: r.end.cmTime))
                    p.setVolume(v, at: r.end.cmTime)
                } else {
                    p.setVolume(v, at: placement.start.cmTime)
                }
                let next = placement.index + 1 < layout.placements.count ? layout.placements[placement.index + 1] : nil
                if let next, let r = next.transitionRange {
                    p.setVolumeRamp(fromStartVolume: v, toEndVolume: 0, timeRange: CMTimeRange(start: r.start.cmTime, end: r.end.cmTime))
                } else {
                    p.setVolume(0, at: placement.end.cmTime)
                }
            }
            params.append(p)
        }

        for clip in project.musicTrack {
            guard let track = musicTracks[clip.id] else { continue }
            let p = AVMutableAudioMixInputParameters(track: track)
            // 音量 × 轨道 × 淡入淡出 × 人声避让，按分段线性包络设置
            let points = project.volumeEnvelope(for: clip).points
            if let first = points.first { p.setVolume(Float(first.gain), at: first.time.cmTime) }
            for (a, b) in zip(points, points.dropFirst()) where b.time > a.time {
                p.setVolumeRamp(fromStartVolume: Float(a.gain), toEndVolume: Float(b.gain),
                                timeRange: CMTimeRange(start: a.time.cmTime, end: b.time.cmTime))
            }
            params.append(p)
        }

        let mix = AVMutableAudioMix()
        mix.inputParameters = params
        return mix
    }
}

public enum CompositionBuilder {
    /// 只包含影响轨道结构与时间的字段；相同则只需重建视频指令与混音。
    public struct StructureKey: Hashable, Sendable {
        var parts: [String]
    }

    public static func structureKey(_ project: Project, includeMusic: Bool = true) -> StructureKey {
        let layout = TimelineLayout(project: project)
        var parts: [String] = []
        for (clip, placement) in zip(project.mainTrack, layout.placements) {
            let path = project.asset(id: clip.assetID)?.path ?? "?"
            parts.append("v|\(clip.id)|\(path)|\(clip.sourceIn.microseconds)|\(clip.sourceOut.microseconds)|\(clip.speed)|\(placement.start.microseconds)")
        }
        if includeMusic {
            for m in project.musicTrack {
                let path = project.asset(id: m.assetID)?.path ?? "?"
                parts.append("m|\(m.id)|\(path)|\(m.start.microseconds)|\(m.sourceIn.microseconds)|\(m.sourceOut.microseconds)")
            }
        }
        return StructureKey(parts: parts)
    }

    public static func build(project: Project, renderSize: CGSize, includeMusic: Bool = true) async throws -> BuiltComposition {
        let layout = TimelineLayout(project: project)
        guard !layout.placements.isEmpty, layout.duration > .zero else { throw CompositionError.empty }

        let composition = AVMutableComposition()
        var assets: [String: AVURLAsset] = [:]
        func avAsset(_ asset: MediaAsset) throws -> AVURLAsset {
            guard FileManager.default.fileExists(atPath: asset.path) else { throw CompositionError.missingAsset(asset.name) }
            if let a = assets[asset.path] { return a }
            let a = AVURLAsset(url: asset.url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
            assets[asset.path] = a
            return a
        }

        var videoLanes: [AVMutableCompositionTrack?] = [nil, nil]
        var audioLanes: [AVMutableCompositionTrack?] = [nil, nil]
        func lane(_ lanes: inout [AVMutableCompositionTrack?], _ i: Int, _ type: AVMediaType) -> AVMutableCompositionTrack? {
            if lanes[i] == nil { lanes[i] = composition.addMutableTrack(withMediaType: type, preferredTrackID: kCMPersistentTrackID_Invalid) }
            return lanes[i]
        }

        var videoSources: [UUID: BuiltComposition.VideoSource] = [:]
        var clipHasAudio = Set<UUID>()

        for placement in layout.placements {
            guard let clip = project.mainClip(id: placement.clipID), let asset = project.asset(id: clip.assetID) else { continue }
            guard asset.kind == .video else { continue }
            let av = try avAsset(asset)
            let wanted = CMTimeRange(start: clip.sourceIn.cmTime, end: clip.sourceOut.cmTime)

            if let srcVideo = try await av.loadTracks(withMediaType: .video).first,
               let track = lane(&videoLanes, placement.lane, .video) {
                let (srcRange, size, transform) = try await srcVideo.load(.timeRange, .naturalSize, .preferredTransform)
                let range = wanted.intersection(srcRange)
                if range.duration > .zero {
                    try insert(range, of: srcVideo, into: track, at: placement.start, scaledTo: placement.duration, speed: clip.speed)
                    videoSources[clip.id] = .init(trackID: track.trackID, naturalSize: size, preferredTransform: transform)
                }
            }
            if let srcAudio = try await av.loadTracks(withMediaType: .audio).first,
               let track = lane(&audioLanes, placement.lane, .audio) {
                let srcRange = try await srcAudio.load(.timeRange)
                let range = wanted.intersection(srcRange)
                if range.duration > .zero {
                    try insert(range, of: srcAudio, into: track, at: placement.start, scaledTo: placement.duration, speed: clip.speed)
                    clipHasAudio.insert(clip.id)
                }
            }
        }

        // 基底轨：黑色小视频拉伸铺满时间线
        let blank = AVURLAsset(url: try await BlankVideo.url())
        guard let blankTrack = try await blank.loadTracks(withMediaType: .video).first,
              let base = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw CompositionError.empty
        }
        let blankRange = try await blankTrack.load(.timeRange)
        try base.insertTimeRange(blankRange, of: blankTrack, at: .zero)
        base.scaleTimeRange(CMTimeRange(start: .zero, duration: blankRange.duration), toDuration: layout.duration.cmTime)

        var musicTracks: [UUID: AVMutableCompositionTrack] = [:]
        if includeMusic {
            for clip in project.musicTrack {
                guard let asset = project.asset(id: clip.assetID) else { continue }
                let av = try avAsset(asset)
                guard let src = try await av.loadTracks(withMediaType: .audio).first,
                      let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else { continue }
                let srcRange = try await src.load(.timeRange)
                let range = CMTimeRange(start: clip.sourceIn.cmTime, end: clip.sourceOut.cmTime).intersection(srcRange)
                guard range.duration > .zero else { continue }
                if clip.start > .zero { track.insertEmptyTimeRange(CMTimeRange(start: .zero, duration: clip.start.cmTime)) }
                try track.insertTimeRange(range, of: src, at: clip.start.cmTime)
                musicTracks[clip.id] = track
            }
        }

        return BuiltComposition(composition: composition, duration: layout.duration,
                                structureKey: structureKey(project, includeMusic: includeMusic),
                                baseTrackID: base.trackID, videoSources: videoSources, laneAudioTracks: audioLanes,
                                clipHasAudio: clipHasAudio, musicTracks: musicTracks)
    }

    /// 在轨道末尾（start 处）插入源区间并按速度缩放。
    private static func insert(_ range: CMTimeRange, of source: AVAssetTrack, into track: AVMutableCompositionTrack,
                               at start: Time, scaledTo duration: Time, speed: Double) throws {
        let trackEnd = Time(track.timeRange.end)
        var at = start
        if trackEnd < start {
            track.insertEmptyTimeRange(CMTimeRange(start: trackEnd.cmTime, end: start.cmTime))
        } else if trackEnd > start {
            at = trackEnd // 只可能是取整误差
        }
        try track.insertTimeRange(range, of: source, at: at.cmTime)
        if speed != 1 {
            let target = Time(range.duration) / speed
            track.scaleTimeRange(CMTimeRange(start: at.cmTime, duration: range.duration), toDuration: target.cmTime)
        }
    }
}
