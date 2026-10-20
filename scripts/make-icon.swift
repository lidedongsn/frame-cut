// 配色取自 App 主题（App/Theme.swift）：石墨深灰底、强调青 (0.16,0.82,0.86)、播放头黄 (1,0.85,0.25)。
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

/// 苹果图标外形：四边笔直，转角用超椭圆过渡（曲率连续，比普通圆角更柔和，不会出现边缘鼓起）。
func squircle(_ r: CGRect, extent e: CGFloat = 0.33, n: CGFloat = 4.2) -> CGPath {
    let k = r.width * e
    let path = CGMutablePath()
    // 每个转角：以 (cx, cy) 为超椭圆中心、k 为半轴的四分之一段
    let corners: [(CGFloat, CGFloat, CGFloat)] = [
        (r.maxX - k, r.maxY - k, 0), (r.minX + k, r.maxY - k, .pi / 2),
        (r.minX + k, r.minY + k, .pi), (r.maxX - k, r.minY + k, .pi * 1.5),
    ]
    for (idx, (cx, cy, start)) in corners.enumerated() {
        let steps = 90
        for i in 0...steps {
            let t = start + CGFloat(i) / CGFloat(steps) * .pi / 2
            let c = cos(t), s = sin(t)
            let p = CGPoint(x: cx + k * (c < 0 ? -1 : 1) * pow(abs(c), 2 / n), y: cy + k * (s < 0 ? -1 : 1) * pow(abs(s), 2 / n))
            if idx == 0 && i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
    }
    path.closeSubpath()
    return path
}

/// 前景元素：先画柔和投影（光从上方来），再用竖向渐变填充。
func drawRaised(_ ctx: CGContext, _ path: CGPath, top: (CGFloat, CGFloat, CGFloat), bottom: (CGFloat, CGFloat, CGFloat), lift: CGFloat = 1) {
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10 * lift), blur: 22 * lift, color: color(0, 0, 0, 0.5))
    ctx.addPath(path)
    ctx.setFillColor(color(bottom.0, bottom.1, bottom.2))
    ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    fillVertical(ctx, path.boundingBoxOfPath.insetBy(dx: -2, dy: -2), top: top, bottom: bottom)
    ctx.restoreGState()
}

/// detail 为 false 时（64px 及以下）简化：去掉取景框、放大字标、C 不切开，避免小图里糊成一团。
func drawIcon(_ ctx: CGContext, detail: Bool) {
    // 苹果图标规范：1024 画布中主体 824×824，留出投影空间
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let bodyPath = squircle(body)

    // 图标整体投影
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 30, color: color(0, 0, 0, 0.4))
    ctx.addPath(bodyPath)
    ctx.setFillColor(color(0.07, 0.07, 0.08))
    ctx.fillPath()
    ctx.restoreGState()

    // 背景：与界面一致的中性石墨灰（窗口 0.067 / 面板 0.10 / 凸起 0.145），上亮下暗
    ctx.saveGState()
    ctx.addPath(bodyPath)
    ctx.clip()
    fillVertical(ctx, body, top: (0.18, 0.18, 0.20), bottom: (0.067, 0.067, 0.078))
    // 顶边高光：一圈细亮边，越往下越淡
    ctx.addPath(bodyPath.copy(strokingWithWidth: 6, lineCap: .round, lineJoin: .round, miterLimit: 10))
    ctx.clip()
    fillVertical(ctx, body, top: (0.42, 0.42, 0.45), bottom: (0.067, 0.067, 0.078))
    ctx.restoreGState()

    if detail {
        // 取景框四角
        let inset: CGFloat = 250, len: CGFloat = 140, w: CGFloat = 44
        let lo = inset, hi = S - inset
        let corners = CGMutablePath()
        for (x, y, dx, dy) in [(lo, hi, 1.0, -1.0), (hi, hi, -1.0, -1.0), (lo, lo, 1.0, 1.0), (hi, lo, -1.0, 1.0)] as [(CGFloat, CGFloat, CGFloat, CGFloat)] {
            corners.move(to: CGPoint(x: x + dx * len, y: y))
            corners.addLine(to: CGPoint(x: x, y: y))
            corners.addLine(to: CGPoint(x: x, y: y + dy * len))
        }
        let stroke = corners.copy(strokingWithWidth: w, lineCap: .round, lineJoin: .round, miterLimit: 10)
        // 强调青：顶部略提亮表现受光，主体就是界面的强调色
        drawRaised(ctx, stroke, top: (0.36, 0.92, 0.94), bottom: (0.16, 0.82, 0.86), lift: 0.6)
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

/// 中心标识：SF Pro 特粗 “FC”，C（Cut）被一道斜线切开并轻微错位。F 白、C 播放头黄。
func drawMonogram(_ ctx: CGContext, cut: Bool) {
    let size: CGFloat = cut ? 330 : 480
    let font = NSFont.systemFont(ofSize: size, weight: cut ? .heavy : .bold)
    let f = textPath("F", font: font as CTFont), c = textPath("C", font: font as CTFont)
    let fb = f.boundingBoxOfPath, cb = c.boundingBoxOfPath
    let kerning: CGFloat = cut ? 22 : 30
    let total = fb.width + kerning + cb.width
    let height = max(fb.height, cb.height)
    let x0 = 512 - total / 2, y0 = 512 - height / 2
    var tf = CGAffineTransform(translationX: x0 - fb.minX, y: y0 - fb.minY)
    var tc = CGAffineTransform(translationX: x0 + fb.width + kerning - cb.minX, y: y0 - cb.minY)
    let fPath = f.copy(using: &tf)!, cPath = c.copy(using: &tc)!

    let white = ((CGFloat(1), CGFloat(1), CGFloat(1)), (CGFloat(0.84), CGFloat(0.84), CGFloat(0.86)))
    // 播放头黄：顶部略亮，底部就是界面的播放头色
    let yellow = ((CGFloat(1), CGFloat(0.92), CGFloat(0.45)), (CGFloat(1), CGFloat(0.85), CGFloat(0.25)))
    drawRaised(ctx, fPath, top: white.0, bottom: white.1)

    guard cut else {
        drawRaised(ctx, cPath, top: yellow.0, bottom: yellow.1)
        return
    }
    // 用路径布尔运算把 C 沿斜线分成两块，各自错开一点
    let center = CGPoint(x: cPath.boundingBoxOfPath.midX, y: cPath.boundingBoxOfPath.midY)
    let angle: CGFloat = .pi * 0.30
    let dir = CGPoint(x: cos(angle), y: sin(angle)), normal = CGPoint(x: -dir.y, y: dir.x)
    let gap: CGFloat = 8, shift: CGFloat = 7, far: CGFloat = 1200
    for side in [1.0, -1.0] as [CGFloat] {
        let o = CGPoint(x: center.x + normal.x * gap * side, y: center.y + normal.y * gap * side)
        let half = CGMutablePath()
        half.move(to: CGPoint(x: o.x - dir.x * far, y: o.y - dir.y * far))
        half.addLine(to: CGPoint(x: o.x + dir.x * far, y: o.y + dir.y * far))
        half.addLine(to: CGPoint(x: o.x + dir.x * far + normal.x * far * side, y: o.y + dir.y * far + normal.y * far * side))
        half.addLine(to: CGPoint(x: o.x - dir.x * far + normal.x * far * side, y: o.y - dir.y * far + normal.y * far * side))
        half.closeSubpath()
        var move = CGAffineTransform(translationX: normal.x * shift * side, y: normal.y * shift * side)
        let piece = cPath.intersection(half).copy(using: &move)!
        drawRaised(ctx, piece, top: yellow.0, bottom: yellow.1)
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
