// 生成 FrameCut 应用图标：取景框四角（Frame）+ 被斜切成两半的播放键（Cut）。
// 用法：swift scripts/make-icon.swift <输出目录>   → 输出 AppIcon.appiconset 所需的各尺寸 PNG
import AppKit
import CoreGraphics

let S: CGFloat = 1024

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r, green: g, blue: b, alpha: a)
}

/// 竖向渐变：逐行填纯色。系统的 CGGradient 会加抖动噪点，PNG 几乎压不动（1024 图从约 50KB 涨到 600KB+）。
func fillVertical(_ ctx: CGContext, _ rect: CGRect, top: (CGFloat, CGFloat, CGFloat), bottom: (CGFloat, CGFloat, CGFloat)) {
    let rows = Int(rect.height.rounded(.up))
    for i in 0..<rows {
        let t = CGFloat(i) / CGFloat(max(1, rows - 1))
        ctx.setFillColor(color(bottom.0 + (top.0 - bottom.0) * t, bottom.1 + (top.1 - bottom.1) * t, bottom.2 + (top.2 - bottom.2) * t))
        ctx.fill(CGRect(x: rect.minX, y: rect.minY + CGFloat(i), width: rect.width, height: 1))
    }
}

func drawIcon(_ ctx: CGContext) {
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

    // 播放键：圆角三角形，沿斜线切成两块并错开
    let cx: CGFloat = 528, cy: CGFloat = 512, h: CGFloat = 330
    let tri = CGMutablePath()
    let a = CGPoint(x: cx - h * 0.42, y: cy + h / 2), b = CGPoint(x: cx - h * 0.42, y: cy - h / 2), c = CGPoint(x: cx + h * 0.5, y: cy)
    tri.move(to: CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2))
    tri.addArc(tangent1End: b, tangent2End: c, radius: 34)
    tri.addArc(tangent1End: c, tangent2End: a, radius: 34)
    tri.addArc(tangent1End: a, tangent2End: b, radius: 34)
    tri.closeSubpath()

    // 切线：经过三角形中心、自左下到右上
    let angle: CGFloat = .pi * 0.30
    let dir = CGPoint(x: cos(angle), y: sin(angle)), normal = CGPoint(x: -dir.y, y: dir.x)
    let gap: CGFloat = 7, shift: CGFloat = 5
    for side in [1.0, -1.0] as [CGFloat] {
        ctx.saveGState()
        // 每块向切线法向外移一点，留出缝隙
        ctx.translateBy(x: normal.x * shift * side, y: normal.y * shift * side)
        let half = CGMutablePath()
        let o = CGPoint(x: cx - 30 + normal.x * gap * side, y: cy + normal.y * gap * side)
        let far: CGFloat = 1000
        half.move(to: CGPoint(x: o.x - dir.x * far, y: o.y - dir.y * far))
        half.addLine(to: CGPoint(x: o.x + dir.x * far, y: o.y + dir.y * far))
        half.addLine(to: CGPoint(x: o.x + dir.x * far + normal.x * far * side, y: o.y + dir.y * far + normal.y * far * side))
        half.addLine(to: CGPoint(x: o.x - dir.x * far + normal.x * far * side, y: o.y - dir.y * far + normal.y * far * side))
        half.closeSubpath()
        ctx.addPath(half)
        ctx.clip()
        ctx.addPath(tri)
        ctx.clip()
        let triRect = CGRect(x: cx - h, y: cy - h / 2 - 20, width: 2 * h, height: h + 40)
        if side > 0 {
            fillVertical(ctx, triRect, top: (1, 0.90, 0.40), bottom: (1, 0.74, 0.20))
        } else {
            fillVertical(ctx, triRect, top: (1, 1, 1), bottom: (0.86, 0.89, 0.93))
        }
        ctx.restoreGState()
    }
}

func png(size: Int) -> Data {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.scaleBy(x: CGFloat(size) / S, y: CGFloat(size) / S)
    drawIcon(ctx)
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
