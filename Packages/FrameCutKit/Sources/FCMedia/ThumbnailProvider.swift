import AVFoundation
import CoreGraphics
import FCCore
import Foundation
import ImageIO

/// 视频 / 图片缩略图，内存缓存。时间按 0.5 秒取整以提高命中率。
public actor ThumbnailProvider {
    public static let shared = ThumbnailProvider()

    private let cache = NSCache<NSString, CGImage>()
    private var generators: [URL: AVAssetImageGenerator] = [:]

    /// HDR 帧的色调映射（由引擎注入，FCMedia 不依赖渲染引擎）。
    nonisolated(unsafe) public static var hdrToneMapper: (@Sendable (CGImage, HDRFormat) -> CGImage?)?

    public init() {
        cache.countLimit = 2000
    }

    public func thumbnail(url: URL, time: Time, maxHeight: CGFloat, hdr: HDRFormat? = nil) async -> CGImage? {
        let bucket = (time.seconds * 2).rounded() / 2
        let key = "\(url.path)|\(bucket)|\(Int(maxHeight))|\(hdr?.rawValue ?? "")" as NSString
        if let hit = cache.object(forKey: key) { return hit }

        var image: CGImage?
        if isImageFile(url) {
            image = imageThumbnail(url: url, maxPixel: maxHeight * 2)
        } else {
            let generator = generator(for: url, maxHeight: maxHeight)
            let cmTime = CMTime(seconds: bucket, preferredTimescale: 600)
            image = try? await generator.image(at: cmTime).image
        }
        if let hdr, let raw = image, let mapper = Self.hdrToneMapper {
            image = mapper(raw, hdr)
        }
        if let image { cache.setObject(image, forKey: key) }
        return image
    }

    private func generator(for url: URL, maxHeight: CGFloat) -> AVAssetImageGenerator {
        if let g = generators[url] { return g }
        let g = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        g.appliesPreferredTrackTransform = true
        g.maximumSize = CGSize(width: maxHeight * 4, height: maxHeight * 2)
        g.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
        g.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)
        generators[url] = g
        return g
    }

    private func isImageFile(_ url: URL) -> Bool {
        ["jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "gif", "bmp", "webp"].contains(url.pathExtension.lowercased())
    }

    private func imageThumbnail(url: URL, maxPixel: CGFloat) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(maxPixel),
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
