import AVFoundation
import CoreVideo

/// AVFoundation 自定义合成器，把每个请求交给 FrameRenderer。
/// 源帧按 10 位请求，HDR 源不会在解码时被压成 8 位；输出格式由子类决定。
class CompositorBridge: NSObject, AVVideoCompositing {
    class var outputPixelFormat: OSType { kCVPixelFormatType_32BGRA }

    let supportsHDRSourceFrames = true
    let supportsWideColorSourceFrames = true

    private let queue = DispatchQueue(label: "framecut.compositor", qos: .userInteractive)
    private let lock = NSLock()
    private var generation = 0

    let sourcePixelBufferAttributes: [String: any Sendable]? = [
        kCVPixelBufferPixelFormatTypeKey as String: [
            kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange,
            kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
            kCVPixelFormatType_32BGRA,
        ],
        kCVPixelBufferMetalCompatibilityKey as String: true,
        kCVPixelBufferIOSurfacePropertiesKey as String: [String: any Sendable](),
    ]

    var requiredPixelBufferAttributesForRenderContext: [String: any Sendable] {
        [
            kCVPixelBufferPixelFormatTypeKey as String: Self.outputPixelFormat,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: any Sendable](),
        ]
    }

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {}

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        lock.lock()
        let generation = self.generation
        lock.unlock()
        queue.async { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let stale = generation != self.generation
            self.lock.unlock()
            if stale {
                request.finishCancelledRequest()
                return
            }
            do {
                let start = DispatchTime.now().uptimeNanoseconds
                let buffer = try FrameRenderer.shared.render(request)
                RenderTimer.preview.record(ms: Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
                request.finish(withComposedVideoFrame: buffer)
            } catch {
                request.finish(with: error)
            }
        }
    }

    /// 取消：递增代数，已排队但未开始的旧请求直接取消。
    func cancelAllPendingVideoCompositionRequests() {
        lock.lock()
        generation &+= 1
        lock.unlock()
    }
}

/// SDR 输出：8 位 BGRA。
final class SDRCompositor: CompositorBridge {}

/// HDR 输出：半精度浮点 RGBA，承载 HLG / PQ 编码值。
final class HDRCompositor: CompositorBridge {
    override class var outputPixelFormat: OSType { kCVPixelFormatType_64RGBAHalf }
}
