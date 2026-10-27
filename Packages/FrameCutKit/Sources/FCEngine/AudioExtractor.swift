import AVFoundation
import FCCore
import Foundation

/// 时间线声音（视频原声和 / 或音频轨，已应用音量 / 静音 / 变速 / 淡入淡出）→ 16kHz 单声道 Float，时间与时间线一致。
public enum AudioExtractor {
    public static let sampleRate = 16_000

    /// original：视频原声（主轨上的，以及分离到音频轨上的）；music：音频轨上的其他声音（配乐、旁白）。
    /// 两者都不选或都没有声音时返回空。
    public static func samples(project: Project, original: Bool = true, music: Bool = false) async throws -> [Float] {
        let wanted = project.musicTrack.filter { project.isOriginalSound($0) ? original : music }.map(\.id)
        let built = try await CompositionBuilder.build(project: project, renderSize: CGSize(width: 64, height: 64),
                                                       includeMusic: !wanted.isEmpty)
        let tracks = (original ? built.laneAudioTracks.compactMap { $0 } : []) + wanted.compactMap { built.musicTracks[$0] }
        guard !tracks.isEmpty else { return [] }

        let reader = try AVAssetReader(asset: built.composition)
        reader.timeRange = CMTimeRange(start: .zero, duration: built.duration.cmTime)
        let output = AVAssetReaderAudioMixOutput(audioTracks: tracks, audioSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: sampleRate, AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true, AVLinearPCMIsNonInterleaved: false,
        ])
        output.audioMix = built.makeAudioMix(project: project)
        output.audioTimePitchAlgorithm = .spectral
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? ExportError.failed(String(localized: "无法读取音频", bundle: .module)) }

        var samples: [Float] = []
        samples.reserveCapacity(Int(built.duration.seconds * Double(sampleRate)) + sampleRate)
        while let buffer = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
            var length = 0
            var pointer: UnsafeMutablePointer<Int8>?
            guard CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length,
                                              dataPointerOut: &pointer) == kCMBlockBufferNoErr, let pointer else { continue }
            let count = length / MemoryLayout<Float>.size
            pointer.withMemoryRebound(to: Float.self, capacity: count) { samples.append(contentsOf: UnsafeBufferPointer(start: $0, count: count)) }
        }
        if reader.status == .failed { throw reader.error ?? ExportError.failed(String(localized: "读取音频失败", bundle: .module)) }
        return samples
    }
}
