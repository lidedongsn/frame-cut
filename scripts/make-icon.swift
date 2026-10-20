// 生成 FrameCut 应用图标：取景框四角（Frame）+ 被斜切开的 “FC” 字标（Cut）。
// 用法：swift scripts/make-icon.swift <输出目录>   → 输出 AppIcon.appiconset 所需的各尺寸 PNG
import AppKit
import CoreGraphics

let S: CGFloat = 1024

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r, green: g, blue: b, alpha: a)
}

/// 竖向渐变：逐行填纯色。系统的 CGGradient 会加抖动噪点，PNG 几乎压不动（1024 图从约 50KB 涨到 600KB+）。
func fillVertical(_ ctx: CGContext, _ area: CGRect, top: (CGFloat, CGFloat, CGFloat), bottom: (CGFloat, CGFloat, CGFloat)) {
    // 对齐整数像素并关闭色带抗锯齿：否则每条色带半盖两行像素，与底色叠加后整体发暗（边缘抗锯齿由裁切路径保留）
    let rect = area.integral
    ctx.saveGState()
    defer { ctx.restoreGState() }
    ctx.setShouldAntialias(false)
    let rows = Int(rect.height)
    for i in 0..<rows {
        let t = CGFloat(i) / CGFloat(max(1, rows - 1))
        ctx.setFillColor(color(bottom.0 + (top.0 - bottom.0) * t, bottom.1 + (top.1 - bottom.1) * t, bottom.2 + (top.2 - bottom.2) * t))
        ctx.fill(CGRect(x: rect.minX, y: rect.minY + CGFloat(i), width: rect.width, height: 1))
    }
}

/// detail 为 false 时（64px 及以下）简化：去掉取景框、放大字标、C 不切开，避免小图里糊成一团。
func drawIcon(_ ctx: CGContext, detail: Bool) {
    // 苹果图标规范：1024 画布中主体 824×824，留出投影空间
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let bodyPath = CGPath(roundedRect: body, cornerWidth: 186, cornerHeight: 186, transform: nil)

    // 投影
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: color(0, 0, 0, 0.45))
    ctx.addPath(bodyPath)
    ctx.setFillColor(color(0.08, 0.09, 0.11))
    ctx.fillPath()
    ctx.restoreGState()

    // 背景：深色竖向渐变 + 顶部微光
    ctx.saveGState()
    ctx.addPath(bodyPath)
    ctx.clip()
    fillVertical(ctx, body, top: (0.17, 0.21, 0.26), bottom: (0.06, 0.07, 0.09))
    ctx.restoreGState()

    if detail {
        // 取景框四角（青色渐变描边）
        let inset: CGFloat = 250, len: CGFloat = 150, w: CGFloat = 50
        let lo = inset, hi = S - inset
        let corners = CGMutablePath()
        for (x, y, dx, dy) in [(lo, hi, 1.0, -1.0), (hi, hi, -1.0, -1.0), (lo, lo, 1.0, 1.0), (hi, lo, -1.0, 1.0)] as [(CGFloat, CGFloat, CGFloat, CGFloat)] {
            corners.move(to: CGPoint(x: x + dx * len, y: y))
            corners.addLine(to: CGPoint(x: x, y: y))
            corners.addLine(to: CGPoint(x: x, y: y + dy * len))
        }
        ctx.saveGState()
        ctx.addPath(corners.copy(strokingWithWidth: w, lineCap: .round, lineJoin: .round, miterLimit: 10))
        ctx.clip()
        fillVertical(ctx, CGRect(x: lo - w, y: lo - w, width: hi - lo + 2 * w, height: hi - lo + 2 * w),
                     top: (0.30, 0.92, 0.90), bottom: (0.12, 0.62, 0.92))
        ctx.restoreGState()
    }

    drawMonogram(ctx, cut: detail)
}

/// 文字转路径（可裁切、可渐变填充）。
func textPath(_ text: String, font: CTFont) -> CGPath {
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font]))
    let path = CGMutablePath()
    for run in CTLineGetGlyphRuns(line) as! [CTRun] {
        let count = CTRunGetGlyphCount(run)
        var glyphs = [CGGlyph](repeating: 0, count: count)
        var positions = [CGPoint](repeating: .zero, count: count)
        CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
        CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
        for (g, p) in zip(glyphs, positions) {
            if let gp = CTFontCreatePathForGlyph(font, g, nil) {
                path.addPath(gp, transform: CGAffineTransform(translationX: p.x, y: p.y))
            }
        }
    }
    return path
}

/// 中心标识：粗圆体 “FC”，被一道斜线切开并轻微错位（Cut）。F 白色、C 播放头黄。
func drawMonogram(_ ctx: CGContext, cut: Bool) {
    let size: CGFloat = cut ? 320 : 480
    let base = NSFont.systemFont(ofSize: size, weight: cut ? .heavy : .bold)
    let font = NSFont(descriptor: base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor, size: size) ?? base
    let f = textPath("F", font: font as CTFont), c = textPath("C", font: font as CTFont)
    let fb = f.boundingBoxOfPath, cb = c.boundingBoxOfPath
    let kerning: CGFloat = cut ? 24 : 30
    let total = fb.width + kerning + cb.width
    let height = max(fb.height, cb.height)
    let x0 = 512 - total / 2, y0 = 512 - height / 2
    var tf = CGAffineTransform(translationX: x0 - fb.minX, y: y0 - fb.minY)
    var tc = CGAffineTransform(translationX: x0 + fb.width + kerning - cb.minX, y: y0 - cb.minY)
    let fPath = f.copy(using: &tf)!, cPath = c.copy(using: &tc)!

    // F 完整
    ctx.saveGState()
    ctx.addPath(fPath)
    ctx.clip()
    fillVertical(ctx, fPath.boundingBoxOfPath.insetBy(dx: -2, dy: -2), top: (1, 1, 1), bottom: (0.84, 0.88, 0.93))
    ctx.restoreGState()

    // C（Cut）被一道斜线切开并轻微错位
    let letters: [(CGPath, (CGFloat, CGFloat, CGFloat), (CGFloat, CGFloat, CGFloat))] = [
        (cPath, (1, 0.90, 0.40), (1, 0.72, 0.18)),
    ]
    let center = CGPoint(x: cPath.boundingBoxOfPath.midX, y: cPath.boundingBoxOfPath.midY)
    let angle: CGFloat = .pi * 0.30
    let dir = CGPoint(x: cos(angle), y: sin(angle)), normal = CGPoint(x: -dir.y, y: dir.x)
    let gap: CGFloat = cut ? 8 : 0, shift: CGFloat = cut ? 7 : 0
    for side in [1.0, -1.0] as [CGFloat] {
        ctx.saveGState()
        ctx.translateBy(x: normal.x * shift * side, y: normal.y * shift * side)
        let o = CGPoint(x: center.x + normal.x * gap * side, y: center.y + normal.y * gap * side)
        let far: CGFloat = 1200
        let half = CGMutablePath()
        half.move(to: CGPoint(x: o.x - dir.x * far, y: o.y - dir.y * far))
        half.addLine(to: CGPoint(x: o.x + dir.x * far, y: o.y + dir.y * far))
        half.addLine(to: CGPoint(x: o.x + dir.x * far + normal.x * far * side, y: o.y + dir.y * far + normal.y * far * side))
        half.addLine(to: CGPoint(x: o.x - dir.x * far + normal.x * far * side, y: o.y - dir.y * far + normal.y * far * side))
        half.closeSubpath()
        for (path, top, bottom) in letters {
            ctx.saveGState()
            ctx.addPath(half)
            ctx.clip()
            ctx.addPath(path)
            ctx.clip()
            fillVertical(ctx, path.boundingBoxOfPath.insetBy(dx: -2, dy: -2), top: top, bottom: bottom)
            ctx.restoreGState()
        }
        ctx.restoreGState()
    }
}

func png(size: Int) -> Data {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.scaleBy(x: CGFloat(size) / S, y: CGFloat(size) / S)
    drawIcon(ctx, detail: size > 64)
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    return rep.representation(using: .png, properties: [:])!
}

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.appiconset", isDirectory: true)
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
var images: [[String: String]] = []
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(base)x\(base)\(scale == 2 ? "@2x" : "").png"
        try png(size: base * scale).write(to: out.appendingPathComponent(name))
        images.append(["idiom": "mac", "size": "\(base)x\(base)", "scale": "\(scale)x", "filename": name])
    }
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys]).write(to: out.appendingPathComponent("Contents.json"))
print("→ \(out.path)")
