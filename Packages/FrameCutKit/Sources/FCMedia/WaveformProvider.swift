import AVFoundation
import FCCore
import Foundation

/// 音频波形峰值（0...1），每秒 perSecond 个点，内存缓存。
public actor WaveformProvider {
    public static let shared = WaveformProvider()

    static let cacheLimit = 64

    private var cache = LRUCache<String, [Float]>(capacity: WaveformProvider.cacheLimit)
    private var inFlight: [String: Task<[Float], Never>] = [:]

    public init() {}

    var cachedCount: Int { cache.count }

    public func purge() {
        cache.removeAll()
    }

    public func peaks(url: URL, perSecond: Int = 50) async -> [Float] {
        let key = "\(url.path)|\(perSecond)"
        if let hit = cache[key] { return hit }
        if let task = inFlight[key] { return await task.value }
        let task = Task.detached(priority: .utility) { await Self.extract(url: url, perSecond: perSecond) }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        cache[key] = result
        return result
    }

    private static func extract(url: URL, perSecond: Int) async -> [Float] {
        let sampleRate = 8000
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .audio).first,
              let reader = try? AVAssetReader(asset: asset) else { return [] }
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
        ])
        reader.add(output)
        guard reader.startReading() else { return [] }

        let window = max(1, sampleRate / perSecond)
        var peaks: [Float] = []
        var current: Float = 0
        var count = 0
        while let buffer = output.copyNextSampleBuffer(), let block = CMSampleBufferGetDataBuffer(buffer) {
            var length = 0
            var pointer: UnsafeMutablePointer<Int8>?
            guard CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length,
                                              dataPointerOut: &pointer) == kCMBlockBufferNoErr, let pointer else { continue }
            let samples = length / MemoryLayout<Float>.size
            pointer.withMemoryRebound(to: Float.self, capacity: samples) { floats in
                for i in 0..<samples {
                    current = max(current, abs(floats[i]))
                    count += 1
                    if count == window {
                        peaks.append(min(1, current))
                        current = 0
                        count = 0
                    }
                }
            }
        }
        if count > 0 { peaks.append(min(1, current)) }
        return peaks
    }
}
