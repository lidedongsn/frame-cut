import AVFoundation
import FCCore
import Foundation

public struct ExportSettings: Equatable, Sendable {
    public enum Codec: String, CaseIterable, Sendable {
        case h264, hevc

        public var displayName: String { self == .h264 ? "H.264（兼容性好）" : "HEVC（体积小）" }
    }

    public var shortSide: Int
    public var frameRate: Int
    public var codec: Codec

    public init(shortSide: Int = 1080, frameRate: Int = 30, codec: Codec = .h264) {
        self.shortSide = shortSide
        self.frameRate = frameRate
        self.codec = codec
    }

    /// 按像素数 × 帧率估算码率（bit/s）。
    public func bitrate(for size: CGSize) -> Int {
        let bitsPerPixel = codec == .h264 ? 0.2 : 0.12
        return Int(Double(size.width * size.height) * Double(frameRate) * bitsPerPixel)
    }
}

public enum ExportError: LocalizedError {
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .failed(let reason): "导出失败：\(reason)"
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
        let videoOutput = AVAssetReaderVideoCompositionOutput(videoTracks: videoTracks, videoSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ])
        videoOutput.videoComposition = built.makeVideoComposition(project: project, renderSize: size)
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

        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        writer.shouldOptimizeForNetworkUse = true
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: settings.codec == .h264 ? AVVideoCodecType.h264 : AVVideoCodecType.hevc,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: settings.bitrate(for: size),
                AVVideoExpectedSourceFrameRateKey: settings.frameRate,
                AVVideoMaxKeyFrameIntervalKey: settings.frameRate * 2,
            ],
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
        ])
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

        guard reader.startReading() else { throw ExportError.failed(reader.error?.localizedDescription ?? "无法读取") }
        guard writer.startWriting() else { throw ExportError.failed(writer.error?.localizedDescription ?? "无法写入") }
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
        if reader.status == .failed { throw ExportError.failed(reader.error?.localizedDescription ?? "读取失败") }

        await writer.finishWriting()
        if isCancelled { throw CancellationError() }
        if writer.status != .completed { throw ExportError.failed(writer.error?.localizedDescription ?? "写入失败") }
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
