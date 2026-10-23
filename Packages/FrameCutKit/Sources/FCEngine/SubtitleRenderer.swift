import AppKit
import CoreImage
import CoreText
import FCCore

/// 用 Core Text 把字幕渲染为 CIImage（原点在左下，尺寸为文字包围盒），按文字 + 样式 + 画布尺寸缓存。
public enum SubtitleRenderer {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache = LRUCache<String, CIImage>(capacity: 128)

    static var cachedCount: Int { lock.withLock { cache.count } }

    static func purge() {
        lock.withLock { cache.removeAll() }
    }

    /// visibleCharacters：只画前几个字（打字机效果），其余透明但仍占位，版面与完整文字一致。
    public static func image(text: String, style: SubtitleStyle, canvas: CGSize, visibleCharacters: Int? = nil) -> CIImage? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, canvas.width > 0 else { return nil }
        // 位置不影响位图，不进缓存 key：拖动字幕时不会反复栅格化、也不会挤掉播放用的缓存
        var look = style
        look.horizontalPosition = 0
        look.verticalPosition = 0
        let visible = visibleCharacters.map { min(max(0, $0), trimmed.count) }
        let key = "\(trimmed)|\(look.hashValue)|\(Int(canvas.width))x\(Int(canvas.height))|\(visible ?? -1)"
        if let hit = lock.withLock({ cache[key] }) { return hit }

        let fontSize = max(8, style.fontSize * canvas.height)
        let font = CTFontCreateWithName(style.fontName as CFString, fontSize, nil)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byWordWrapping
        func attributed(color: RGBA, stroke: Double?) -> NSAttributedString {
            var attrs: [NSAttributedString.Key: Any] = [
                .font: font, .paragraphStyle: paragraph, .foregroundColor: cgColor(color),
            ]
            if let stroke {
                attrs[.strokeColor] = cgColor(color)
                attrs[.strokeWidth] = stroke
            }
            let string = NSMutableAttributedString(string: trimmed, attributes: attrs)
            if let visible, visible < trimmed.count {
                let hidden = NSRange(trimmed.index(trimmed.startIndex, offsetBy: visible)..., in: trimmed)
                string.addAttribute(.foregroundColor, value: cgColor(.clear), range: hidden)
                if stroke != nil { string.addAttribute(.strokeColor, value: cgColor(.clear), range: hidden) }
            }
            return string
        }

        let fill = attributed(color: style.textColor, stroke: nil)
        let maxWidth = canvas.width * 0.9
        let framesetter = CTFramesetterCreateWithAttributedString(fill)
        let fit = CTFramesetterSuggestFrameSizeWithConstraints(framesetter, CFRange(), nil,
                                                              CGSize(width: maxWidth, height: .greatestFiniteMagnitude), nil)
        let strokePx = style.strokeWidth > 0 ? style.strokeWidth * fontSize : 0
        let padding = (style.backgroundColor.a > 0 ? fontSize * 0.35 : 0) + strokePx
        let textSize = CGSize(width: ceil(fit.width) + 2, height: ceil(fit.height) + 2)
        let size = CGSize(width: textSize.width + padding * 2, height: textSize.height + padding * 2)

        guard let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        if style.backgroundColor.a > 0 {
            ctx.setFillColor(cgColor(style.backgroundColor))
            let r = fontSize * 0.25
            ctx.addPath(CGPath(roundedRect: CGRect(origin: .zero, size: size), cornerWidth: r, cornerHeight: r, transform: nil))
            ctx.fillPath()
        }
        let textRect = CGRect(x: padding, y: padding, width: textSize.width, height: textSize.height)
        func draw(_ string: NSAttributedString) {
            let fs = CTFramesetterCreateWithAttributedString(string)
            let frame = CTFramesetterCreateFrame(fs, CFRange(), CGPath(rect: textRect, transform: nil), nil)
            CTFrameDraw(frame, ctx)
        }
        if strokePx > 0 {
            // strokeWidth 为字号百分比；正值只描边。描边居中于轮廓，所以取两倍。
            ctx.setLineJoin(.round)
            draw(attributed(color: style.strokeColor, stroke: style.strokeWidth * 200))
        }
        draw(fill)
        guard let cg = ctx.makeImage() else { return nil }
        let image = CIImage(cgImage: cg)
        lock.withLock { cache[key] = image }
        return image
    }

    /// 同一时刻要显示的字幕在画布上的位置（左上角为原点）。多条时按顺序从上到下排开，
    /// 整组按样式的位置居中；每行各自水平居中于设定位置。预览与导出共用。
    public static func layout(_ subtitles: [Subtitle], style: SubtitleStyle, canvas: CGSize) -> [(image: CIImage, rect: CGRect)] {
        let images = subtitles.compactMap { image(text: $0.text, style: style, canvas: canvas) }
        guard !images.isEmpty else { return [] }
        let gap = images.count > 1 ? (style.fontSize * canvas.height * 0.2).rounded() : 0
        let width = images.map(\.extent.width).max() ?? 0
        let height = images.map(\.extent.height).reduce(0, +) + gap * CGFloat(images.count - 1)
        let group = style.frame(textSize: CGSize(width: width, height: height), canvas: canvas)
        var y = group.minY
        return images.map { img in
            let w = img.extent.width, h = img.extent.height
            let x = min(max(0, canvas.width * style.horizontalPosition - w / 2), max(0, canvas.width - w))
            defer { y += h + gap }
            return (img, CGRect(x: x, y: y, width: w, height: h))
        }
    }

    static func cgColor(_ c: RGBA) -> CGColor {
        CGColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: c.a)
    }
}
