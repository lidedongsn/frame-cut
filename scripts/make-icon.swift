// 生成 FrameCut 应用图标：取景框四角（Frame）+ 被斜切成两半的播放键（Cut）。
// 用法：swift scripts/make-icon.swift <输出目录>   → 输出 AppIcon.appiconset 所需的各尺寸 PNG
import AppKit
import CoreGraphics

let S: CGFloat = 1024

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r, green: g, blue: b, alpha: a)
}

func drawIcon(_ ctx: CGContext) {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
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
    let bg = CGGradient(colorsSpace: space, colors: [color(0.17, 0.19, 0.25), color(0.06, 0.07, 0.09)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    let glow = CGGradient(colorsSpace: space, colors: [color(0.16, 0.82, 0.86, 0.22), color(0.16, 0.82, 0.86, 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 540), startRadius: 0, endCenter: CGPoint(x: 512, y: 540), endRadius: 420, options: [])
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
    let teal = CGGradient(colorsSpace: space, colors: [color(0.30, 0.92, 0.90), color(0.12, 0.62, 0.92)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(teal, start: CGPoint(x: lo, y: hi), end: CGPoint(x: hi, y: lo),
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
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
        let fill = side > 0
            ? CGGradient(colorsSpace: space, colors: [color(1, 0.90, 0.40), color(1, 0.74, 0.20)] as CFArray, locations: [0, 1])!
            : CGGradient(colorsSpace: space, colors: [color(1, 1, 1), color(0.86, 0.89, 0.93)] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(fill, start: CGPoint(x: cx, y: cy + h / 2), end: CGPoint(x: cx, y: cy - h / 2),
                               options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
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
