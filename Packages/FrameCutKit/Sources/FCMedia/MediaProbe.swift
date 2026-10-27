import AVFoundation
import FCCore
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum MediaProbeError: LocalizedError {
    case unsupported(String)

    public var errorDescription: String? {
        switch self {
        case .unsupported(let name): String(localized: "不支持的文件：\(name)", bundle: .module)
        }
    }
}

/// 探测素材文件，生成 MediaAsset。
public enum MediaProbe {
    public static let supportedTypes: [UTType] = [.movie, .video, .mpeg4Movie, .quickTimeMovie, .image, .audio]

    public static func probe(url: URL) async throws -> MediaAsset {
        let name = url.lastPathComponent
        let type = UTType(filenameExtension: url.pathExtension.lowercased())
        let bookmark = try? url.bookmarkData(options: .minimalBookmark)

        if let type, type.conforms(to: .image) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  var w = props[kCGImagePropertyPixelWidth] as? Int,
                  var h = props[kCGImagePropertyPixelHeight] as? Int else {
                throw MediaProbeError.unsupported(name)
            }
            // EXIF 方向 5–8 表示旋转 90°
            if let orientation = props[kCGImagePropertyOrientation] as? Int, (5...8).contains(orientation) {
                swap(&w, &h)
            }
            return MediaAsset(kind: .image, name: name, path: url.path, bookmark: bookmark, duration: .zero,
                              width: w, height: h, hasAudio: false, frameRate: 0)
        }

        let asset = AVURLAsset(url: url)
        let duration: CMTime
        let videoTracks: [AVAssetTrack]
        let audioTracks: [AVAssetTrack]
        do {
            duration = try await asset.load(.duration)
            videoTracks = try await asset.loadTracks(withMediaType: .video)
            audioTracks = try await asset.loadTracks(withMediaType: .audio)
        } catch {
            throw MediaProbeError.unsupported(name)
        }

        if let track = videoTracks.first {
            let (size, transform, fps, formats) = try await track.load(.naturalSize, .preferredTransform, .nominalFrameRate, .formatDescriptions)
            let display = size.applying(transform)
            return MediaAsset(kind: .video, name: name, path: url.path, bookmark: bookmark, duration: Time(duration),
                              width: Int(abs(display.width).rounded()), height: Int(abs(display.height).rounded()),
                              hasAudio: !audioTracks.isEmpty, frameRate: Double(fps), hdr: formats.first.flatMap(hdrFormat))
        }
        if !audioTracks.isEmpty, duration.seconds > 0 {
            return MediaAsset(kind: .audio, name: name, path: url.path, bookmark: bookmark, duration: Time(duration),
                              width: 0, height: 0, hasAudio: true, frameRate: 0)
        }
        throw MediaProbeError.unsupported(name)
    }

    /// 从格式描述判断 HDR：传输函数 HLG / PQ；带杜比视界配置的按杜比视界，并区分底层 HLG / PQ。
    static func hdrFormat(_ desc: CMFormatDescription) -> HDRFormat? {
        let ext = CMFormatDescriptionGetExtensions(desc) as? [CFString: Any] ?? [:]
        let transfer = ext[kCMFormatDescriptionExtension_TransferFunction] as? String
        let atoms = ext[kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms] as? [String: Any] ?? [:]
        let codec = CMFormatDescriptionGetMediaSubType(desc)
        let isDolbyVision = atoms.keys.contains { ["dvcC", "dvvC", "dvwC"].contains($0) }
            || codec == fourCC("dvh1") || codec == fourCC("dvhe")
        let hlg = kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG as String
        let pq = kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ as String
        if isDolbyVision { return transfer == pq ? .dolbyVisionPQ : .dolbyVision }
        if transfer == hlg { return .hlg }
        if transfer == pq { return .pq }
        return nil
    }

    private static func fourCC(_ s: String) -> FourCharCode {
        s.utf8.reduce(0) { ($0 << 8) | FourCharCode($1) }
    }
}
