import AVFoundation
import FCCore
import Foundation
import VideoToolbox

public struct ExportSettings: Equatable, Sendable {
    public enum Codec: String, CaseIterable, Sendable {
        case h264, hevc

        public var displayName: String { self == .h264 ? String(localized: "H.264（兼容性好）", bundle: .module) : String(localized: "HEVC（体积小）", bundle: .module) }
    }

    public var shortSide: Int
    public var frameRate: Int
    public var codec: Codec
    public var dynamicRange: DynamicRangeOutput

    public init(shortSide: Int = 1080, frameRate: Int = 30, codec: Codec = .h264, dynamicRange: DynamicRangeOutput = .sdr) {
        self.shortSide = shortSide
        self.frameRate = frameRate
        self.codec = codec
        self.dynamicRange = dynamicRange
    }

    /// HDR 只能用 HEVC（Main10）。
    public var effectiveCodec: Codec { dynamicRange.isHDR ? .hevc : codec }

    /// 按像素数 × 帧率估算码率（bit/s）。
    public func bitrate(for size: CGSize) -> Int {
        let bitsPerPixel = effectiveCodec == .h264 ? 0.2 : (dynamicRange.isHDR ? 0.15 : 0.12)
        return Int(Double(size.width * size.height) * Double(frameRate) * bitsPerPixel)
    }
}

public enum ExportError: LocalizedError {
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .failed(let reason): String(localized: "导出失败：\(reason)", bundle: .module)
        }
    }
}

/// AVAssetReader（合成后的画面与混音）→ AVAssetWriter（硬件编码）。
public final class Exporter: @unchecked Sendable {
    public init() {}

    public func export(project: Project, settings: ExportSettings, to url: URL,
                       progress: @escaping @Sendable (Double) -> Void) async throws {
        var project = project
        project.frameRate = settings.frameRate
        let size = RenderSize.size(aspect: project.aspect, shortSide: settings.shortSide)
        let built = try await CompositionBuilder.build(project: project, renderSize: size)
        try Task.checkCancellation()
        try? FileManager.default.removeItem(at: url)

        let composition = built.composition
        let reader = try AVAssetReader(asset: composition)
        reader.timeRange = CMTimeRange(start: .zero, duration: built.duration.cmTime)

        let videoTracks = try await composition.loadTracks(withMediaType: .video)
        let range = settings.dynamicRange
        // 显式指定输出色彩属性，否则读取端会把合成结果转换到别的色彩空间
        let videoOutput = AVAssetReaderVideoCompositionOutput(videoTracks: videoTracks, videoSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: range.isHDR ? kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange : kCVPixelFormatType_32BGRA,
            AVVideoColorPropertiesKey: range.colorProperties,
        ])
        videoOutput.videoComposition = built.makeVideoComposition(project: project, renderSize: size, output: range)
        videoOutput.alwaysCopiesSampleData = false
        reader.add(videoOutput)

        let audioTracks = try await composition.loadTracks(withMediaType: .audio)
        var audioOutput: AVAssetReaderAudioMixOutput?
        if !audioTracks.isEmpty {
            let out = AVAssetReaderAudioMixOutput(audioTracks: audioTracks, audioSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 2,
                AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsNonInterleaved: false,
                AVLinearPCMIsBigEndianKey: false,
            ])
            out.audioMix = built.makeAudioMix(project: project)
            out.audioTimePitchAlgorithm = .spectral
            out.alwaysCopiesSampleData = false
            reader.add(out)
            audioOutput = out
        }

        let writer = try AVAssetWriter(outputURL: url, fileType: url.pathExtension.lowercased() == "mov" ? .mov : .mp4)
        writer.shouldOptimizeForNetworkUse = true
        let videoSettings = Self.videoSettings(settings, size: size)
        guard writer.canApply(outputSettings: videoSettings, forMediaType: .video) else {
            throw ExportError.failed(String(localized: "编码器不支持当前设置", bundle: .module))
        }
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = false
        writer.add(videoInput)
        var audioInput: AVAssetWriterInput?
        if audioOutput != nil {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 192_000,
            ])
            input.expectsMediaDataInRealTime = false
            writer.add(input)
            audioInput = input
        }

        guard reader.startReading() else { throw ExportError.failed(reader.error?.localizedDescription ?? String(localized: "无法读取", bundle: .module)) }
        guard writer.startWriting() else { throw ExportError.failed(writer.error?.localizedDescription ?? String(localized: "无法写入", bundle: .module)) }
        writer.startSession(atSourceTime: .zero)

        let job = ExportJob(reader: reader, writer: writer, duration: built.duration.seconds, progress: progress)
        do {
            try await withTaskCancellationHandler {
                try await job.run(video: (videoOutput, videoInput), audio: audioOutput.flatMap { o in audioInput.map { (o, $0) } })
            } onCancel: {
                job.cancel()
            }
        } catch {
            reader.cancelReading()
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: url)
            throw error
        }
        progress(1)
    }

    static func videoSettings(_ settings: ExportSettings, size: CGSize) -> [String: Any] {
        let range = settings.dynamicRange
        var compression: [String: Any] = [
            AVVideoAverageBitRateKey: settings.bitrate(for: size),
            AVVideoExpectedSourceFrameRateKey: settings.frameRate,
            AVVideoMaxKeyFrameIntervalKey: settings.frameRate * 2,
        ]
        if range.isHDR {
            compression[AVVideoProfileLevelKey] = kVTProfileLevel_HEVC_Main10_AutoLevel as String
            // 由编码器按输出色彩空间自动写入 HDR 元数据（如杜比视界 / HDR10）
            compression[kVTCompressionPropertyKey_HDRMetadataInsertionMode as String] = kVTHDRMetadataInsertionMode_Auto as String
        }
        if range == .pq {
            compression[kVTCompressionPropertyKey_MasteringDisplayColorVolume as String] = HDR10Metadata.masteringDisplay
            compression[kVTCompressionPropertyKey_ContentLightLevelInfo as String] = HDR10Metadata.contentLightLevel
        }
        return [
            AVVideoCodecKey: settings.effectiveCodec == .h264 ? AVVideoCodecType.h264 : AVVideoCodecType.hevc,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
            AVVideoCompressionPropertiesKey: compression,
            AVVideoColorPropertiesKey: range.colorProperties,
        ]
    }
}

/// HDR10 静态元数据（SMPTE ST 2086 / CTA-861.3，大端序）：P3-D65 母版、1000 尼特。
enum HDR10Metadata {
    static let masteringDisplay: Data = {
        var d = Data()
        func u16(_ v: Double) { d.append(contentsOf: withUnsafeBytes(of: UInt16(v.rounded()).bigEndian, Array.init)) }
        func u32(_ v: Double) { d.append(contentsOf: withUnsafeBytes(of: UInt32(v.rounded()).bigEndian, Array.init)) }
        // 顺序：G、B、R 原色，白点（单位 0.00002）；最大 / 最小亮度（单位 0.0001 尼特）
        for (x, y) in [(0.265, 0.690), (0.150, 0.060), (0.680, 0.320), (0.3127, 0.3290)] {
            u16(x / 0.00002)
            u16(y / 0.00002)
        }
        u32(1000 / 0.0001)
        u32(0.0001 / 0.0001)
        return d
    }()

    /// MaxCLL 1000、MaxFALL 400。
    static let contentLightLevel: Data = {
        var d = Data()
        d.append(contentsOf: withUnsafeBytes(of: UInt16(1000).bigEndian, Array.init))
        d.append(contentsOf: withUnsafeBytes(of: UInt16(400).bigEndian, Array.init))
        return d
    }()
}

/// 两路（画面、声音）并行搬运样本。
private final class ExportJob: @unchecked Sendable {
    let reader: AVAssetReader
    let writer: AVAssetWriter
    let duration: Double
    let progress: @Sendable (Double) -> Void
    private let lock = NSLock()
    private var cancelled = false

    init(reader: AVAssetReader, writer: AVAssetWriter, duration: Double, progress: @escaping @Sendable (Double) -> Void) {
        self.reader = reader
        self.writer = writer
        self.duration = duration
        self.progress = progress
    }

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    func run(video: (AVAssetReaderOutput, AVAssetWriterInput),
             audio: (AVAssetReaderOutput, AVAssetWriterInput)?) async throws {
        let group = DispatchGroup()
        pump(video.0, into: video.1, group: group, reportsProgress: true)
        if let audio { pump(audio.0, into: audio.1, group: group, reportsProgress: false) }

        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            group.notify(queue: .global()) { c.resume() }
        }
        if isCancelled { throw CancellationError() }
        if reader.status == .failed { throw ExportError.failed(reader.error?.localizedDescription ?? String(localized: "读取失败", bundle: .module)) }

        await writer.finishWriting()
        if isCancelled { throw CancellationError() }
        if writer.status != .completed { throw ExportError.failed(writer.error?.localizedDescription ?? String(localized: "写入失败", bundle: .module)) }
    }

    private func pump(_ output: AVAssetReaderOutput, into input: AVAssetWriterInput, group: DispatchGroup, reportsProgress: Bool) {
        group.enter()
        let queue = DispatchQueue(label: "framecut.export.\(input.mediaType.rawValue)")
        var finished = false
        input.requestMediaDataWhenReady(on: queue) { [self] in
            guard !finished else { return }
            while input.isReadyForMoreMediaData {
                if isCancelled || writer.status == .failed {
                    finished = true
                    input.markAsFinished()
                    group.leave()
                    return
                }
                guard let sample = output.copyNextSampleBuffer() else {
                    finished = true
                    input.markAsFinished()
                    group.leave()
                    return
                }
                if reportsProgress, duration > 0 {
                    let t = CMSampleBufferGetPresentationTimeStamp(sample).seconds
                    progress(min(0.99, max(0, t / duration)))
                }
                if !input.append(sample) {
                    finished = true
                    input.markAsFinished()
                    group.leave()
                    return
                }
            }
        }
    }
}
