import AVFoundation
import CoreImage
import FCCore
import ImageIO
import Metal

/// 用 Core Image（Metal 后端）合成一帧：方向 → 填充画幅 → 用户变换 → 滤镜 → 转场 → 字幕。
final class FrameRenderer: @unchecked Sendable {
    static let shared = FrameRenderer()

    let context: CIContext
    private let imageCache = NSCache<NSString, CIImage>()

    /// 半精度浮点 + 扩展线性工作空间：1.0 = 203 尼特参考白，HDR 高光可超过 1.0。
    static let contextOptions: [CIContextOption: Any] = [
        .cacheIntermediates: false,
        .name: "FrameCut",
        .workingFormat: CIFormat.RGBAh,
        .workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!,
    ]

    private init() {
        if let device = MTLCreateSystemDefaultDevice() {
            context = CIContext(mtlDevice: device, options: Self.contextOptions)
        } else {
            context = CIContext(options: Self.contextOptions)
        }
        // 照片解码后常驻内存（4K 照片约 50MB），按字节数限制
        imageCache.countLimit = 32
        imageCache.totalCostLimit = Self.stillImageByteLimit
    }

    static let stillImageByteLimit = 384 * 1024 * 1024

    func purgeImages() {
        imageCache.removeAllObjects()
    }

    func render(_ request: AVAsynchronousVideoCompositionRequest) throws -> CVPixelBuffer {
        guard let instruction = request.videoCompositionInstruction as? RenderInstruction else {
            throw RenderError.badInstruction
        }
        guard let output = request.renderContext.newPixelBuffer() else { throw RenderError.noBuffer }
        let canvas = request.renderContext.size
        let time = Time(request.compositionTime)
        let frame = composeFrame(instruction: instruction, time: time, canvas: canvas) { id in
            request.sourceFrame(byTrackID: id)
        }
        let target = instruction.output
        CVBufferSetAttachment(output, kCVImageBufferColorPrimariesKey, target.colorPrimaries as CFString, .shouldPropagate)
        CVBufferSetAttachment(output, kCVImageBufferTransferFunctionKey, target.transferFunction as CFString, .shouldPropagate)
        CVBufferSetAttachment(output, kCVImageBufferYCbCrMatrixKey, target.yCbCrMatrix as CFString, .shouldPropagate)
        context.render(frame, to: output, bounds: CGRect(origin: .zero, size: canvas), colorSpace: target.colorSpace)
        return output
    }

    func composeFrame(instruction: RenderInstruction, time: Time, canvas: CGSize,
                      source: (CMPersistentTrackID) -> CVPixelBuffer?) -> CIImage {
        let rect = CGRect(origin: .zero, size: canvas)
        let black = CIImage(color: .black).cropped(to: rect)
        let hdrProject = instruction.colorMode == .hdr
        let grading: GradingSpace = hdrProject ? .hlg : .sdr
        let layers: [CIImage] = instruction.layers.map { layer in
            guard var image = sourceImage(layer, source: source) else { return black }
            // SDR 工程中的 HDR 素材：先色调映射，再按 SDR 调色
            if !hdrProject && layer.isHDR { image = ToneMap.apply(image) }
            image = Self.filtered(Self.placed(image, layer: layer, canvas: canvas), layer.filter, space: grading)
            image = Self.effects(image.cropped(to: rect), filter: layer.filter, canvas: canvas)
            // HDR 工程输出 SDR：只映射 HDR 素材（调色之后），普通素材保持原亮度
            if hdrProject && !instruction.output.isHDR && layer.isHDR { image = ToneMap.apply(image) }
            return image.cropped(to: rect).composited(over: black)
        }
        var frame: CIImage
        if let t = instruction.transition, layers.count == 2, t.duration > .zero {
            let p = min(1, max(0, (time - t.start).seconds / t.duration.seconds))
            frame = TransitionRenderer.apply(t.kind, from: layers[0], to: layers[1], progress: p, rect: rect)
        } else {
            frame = layers.last ?? black
        }
        for line in SubtitleRenderer.layout(instruction.scene.activeSubtitles(at: time), style: instruction.scene.style, canvas: canvas) {
            // Core Image 原点在左下
            let y = canvas.height - line.rect.maxY
            frame = line.image.transformed(by: CGAffineTransform(translationX: line.rect.minX.rounded(), y: y.rounded())).composited(over: frame)
        }
        return frame.cropped(to: rect)
    }

    // MARK: 图层

    private func sourceImage(_ layer: LayerSpec, source: (CMPersistentTrackID) -> CVPixelBuffer?) -> CIImage? {
        switch layer.source {
        case .track(let id):
            guard let buffer = source(id) else { return nil }
            return CIImage(cvPixelBuffer: buffer).oriented(Self.orientation(of: layer.preferredTransform))
        case .image(let url):
            return stillImage(url)
        }
    }

    private func stillImage(_ url: URL) -> CIImage? {
        let key = url.path as NSString
        if let hit = imageCache.object(forKey: key) { return hit }
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 4096,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary) else { return nil }
        let image = CIImage(cgImage: cg)
        imageCache.setObject(image, forKey: key, cost: cg.bytesPerRow * cg.height)
        return image
    }

    static func orientation(of t: CGAffineTransform) -> CGImagePropertyOrientation {
        let a = t.a.rounded(), b = t.b.rounded(), c = t.c.rounded(), d = t.d.rounded()
        switch (a, b, c, d) {
        case (0, 1, -1, 0): return .right
        case (0, -1, 1, 0): return .left
        case (-1, 0, 0, -1): return .down
        default: return .up
        }
    }

    /// 用户旋转 → 填充画幅并居中 → 用户缩放与位移。
    static func placed(_ input: CIImage, layer: LayerSpec, canvas: CGSize) -> CIImage {
        var image = input
        switch ((layer.transform.quarterTurns % 4) + 4) % 4 {
        case 1: image = image.oriented(.right)
        case 2: image = image.oriented(.down)
        case 3: image = image.oriented(.left)
        default: break
        }
        image = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
        let w = image.extent.width, h = image.extent.height
        guard w > 0, h > 0 else { return image }
        let scale = max(canvas.width / w, canvas.height / h) * CGFloat(max(0.05, layer.transform.scale))
        let tx = (canvas.width - w * scale) / 2 + CGFloat(layer.transform.offsetX) * canvas.width
        let ty = (canvas.height - h * scale) / 2 - CGFloat(layer.transform.offsetY) * canvas.height
        return image.transformed(by: CGAffineTransform(scaleX: scale, y: scale).concatenating(CGAffineTransform(translationX: tx, y: ty)))
    }

    /// 空间效果：锐化（只作用于亮度）、暗角。
    static func effects(_ input: CIImage, filter f: FilterSettings, canvas: CGSize) -> CIImage {
        var image = input
        let scale = canvas.height / 1080
        if f.sharpen > 0 {
            image = image.clampedToExtent().applyingFilter("CISharpenLuminance", parameters: [
                kCIInputSharpnessKey: f.sharpen * 0.8,
                kCIInputRadiusKey: max(0.5, 1.6 * scale),
            ]).cropped(to: input.extent)
        }
        if f.vignette > 0 {
            let diagonal = hypot(canvas.width, canvas.height)
            image = image.applyingFilter("CIVignetteEffect", parameters: [
                kCIInputCenterKey: CIVector(x: canvas.width / 2, y: canvas.height / 2),
                kCIInputRadiusKey: diagonal * 0.38,
                kCIInputIntensityKey: f.vignette,
                "inputFalloff": 0.6,
            ]).cropped(to: input.extent)
        }
        return image
    }

    static func filtered(_ input: CIImage, _ f: FilterSettings, space: GradingSpace) -> CIImage {
        guard let lut = FilterLUT.data(f, space: space) else { return input }
        return input.applyingFilter("CIColorCubeWithColorSpace", parameters: [
            "inputCubeDimension": FilterLUT.dimension,
            "inputCubeData": lut,
            "inputColorSpace": space.colorSpace,
        ])
    }
}

enum RenderError: Error {
    case badInstruction
    case noBuffer
}

// MARK: - 转场

enum TransitionRenderer {
    static func apply(_ kind: TransitionKind, from a: CIImage, to b: CIImage, progress p: Double, rect: CGRect) -> CIImage {
        let e = p * p * (3 - 2 * p) // smoothstep
        let w = rect.width, h = rect.height
        func shift(_ img: CIImage, _ dx: Double, _ dy: Double) -> CIImage {
            img.transformed(by: CGAffineTransform(translationX: dx, y: dy))
        }
        func dissolve(_ x: CIImage, _ y: CIImage, _ t: Double) -> CIImage {
            x.applyingFilter("CIDissolveTransition", parameters: [kCIInputTargetImageKey: y, kCIInputTimeKey: t])
        }
        let black = CIImage(color: .black).cropped(to: rect)
        let white = CIImage(color: .white).cropped(to: rect)

        switch kind {
        case .dissolve:
            return dissolve(a, b, p)
        case .fadeBlack, .fadeWhite:
            let mid = kind == .fadeBlack ? black : white
            return p < 0.5 ? dissolve(a, mid, p * 2) : dissolve(mid, b, (p - 0.5) * 2)
        case .pushLeft:
            return shift(b, w * (1 - e), 0).composited(over: shift(a, -w * e, 0)).cropped(to: rect)
        case .pushRight:
            return shift(b, -w * (1 - e), 0).composited(over: shift(a, w * e, 0)).cropped(to: rect)
        case .pushUp: // 画面向上移动（CI 坐标 y 向上）
            return shift(b, 0, -h * (1 - e)).composited(over: shift(a, 0, h * e)).cropped(to: rect)
        case .pushDown:
            return shift(b, 0, h * (1 - e)).composited(over: shift(a, 0, -h * e)).cropped(to: rect)
        case .slideLeft:
            return shift(b, w * (1 - e), 0).composited(over: a).cropped(to: rect)
        case .wipeLeft:
            let edge = w * (1 - e)
            let mask = CIImage(color: .white).cropped(to: CGRect(x: edge, y: 0, width: w - edge, height: h)).composited(over: black)
            return b.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: a, kCIInputMaskImageKey: mask])
        case .zoom:
            let s = 1 + 0.6 * e
            let zoomed = a.transformed(by: CGAffineTransform(translationX: -w / 2, y: -h / 2)
                .concatenating(CGAffineTransform(scaleX: s, y: s))
                .concatenating(CGAffineTransform(translationX: w / 2, y: h / 2))).cropped(to: rect)
            return dissolve(zoomed, b, e)
        case .blur:
            let radius = sin(p * .pi) * 30 * h / 1080
            func blurred(_ img: CIImage) -> CIImage {
                radius < 0.5 ? img : img.clampedToExtent().applyingGaussianBlur(sigma: radius).cropped(to: rect)
            }
            return dissolve(blurred(a), blurred(b), e)
        }
    }
}

// MARK: - 滤镜预览（素材库中的滤镜缩略图）

public enum FilterPreview {
    public static func render(_ image: CGImage, preset: FilterPreset) -> CGImage? {
        render(image, settings: FilterSettings(preset: preset))
    }

    public static func render(_ image: CGImage, lut: UserLUTRef) -> CGImage? {
        var f = FilterSettings()
        f.selectLUT(lut)
        return render(image, settings: f)
    }

    public static func render(_ image: CGImage, settings: FilterSettings) -> CGImage? {
        let input = CIImage(cgImage: image)
        let output = FrameRenderer.filtered(input, settings, space: .sdr)
        return FrameRenderer.shared.context.createCGImage(output, from: input.extent)
    }
}

/// 渲染相关的内存缓存（照片、滤镜 LUT、字幕图），关闭工程或内存紧张时释放。
public enum RenderCaches {
    public static func purge() {
        FrameRenderer.shared.purgeImages()
        FilterLUT.purge()
        SubtitleRenderer.purge()
        RenderTimer.preview.reset()
    }
}
