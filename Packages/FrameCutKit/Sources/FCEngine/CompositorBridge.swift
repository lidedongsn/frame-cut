import AVFoundation
import CoreVideo

/// AVFoundation 自定义合成器，把每个请求交给 FrameRenderer。
final class CompositorBridge: NSObject, AVVideoCompositing {
    private let queue = DispatchQueue(label: "framecut.compositor", qos: .userInteractive)
    private let lock = NSLock()
    private var generation = 0

    let sourcePixelBufferAttributes: [String: any Sendable]? = [
        kCVPixelBufferPixelFormatTypeKey as String: [
            kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
            kCVPixelFormatType_32BGRA,
        ],
        kCVPixelBufferMetalCompatibilityKey as String: true,
        kCVPixelBufferIOSurfacePropertiesKey as String: [String: any Sendable](),
    ]

    let requiredPixelBufferAttributesForRenderContext: [String: any Sendable] = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferMetalCompatibilityKey as String: true,
        kCVPixelBufferIOSurfacePropertiesKey as String: [String: any Sendable](),
    ]

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
                let buffer = try FrameRenderer.shared.render(request)
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
