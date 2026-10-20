// 生成仓库分享图（1280×640，GitHub Social preview / README 横幅）。
// 用法：swift scripts/make-social-preview.swift <图标1024.png> <输出.png>
import AppKit

let args = CommandLine.arguments
let icon = NSImage(contentsOfFile: args[1])!
let out = URL(fileURLWithPath: args[2])
let W = 1280, H = 640

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: W, pixelsHigh: H, bitsPerSample: 8, samplesPerPixel: 4,
                           hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// 背景：界面的石墨灰，左上略亮
NSGradient(starting: NSColor(srgbRed: 0.15, green: 0.15, blue: 0.17, alpha: 1),
           ending: NSColor(srgbRed: 0.067, green: 0.067, blue: 0.078, alpha: 1))!
    .draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: -35)

icon.draw(in: NSRect(x: 70, y: 150, width: 340, height: 340))

func text(_ s: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, at p: NSPoint) {
    NSAttributedString(string: s, attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color]).draw(at: p)
}
let accent = NSColor(srgbRed: 0.16, green: 0.82, blue: 0.86, alpha: 1)
text("FrameCut", size: 92, weight: .heavy, color: .white, at: NSPoint(x: 450, y: 390))
text("为 Apple 芯片 Mac 打造的 vlog 剪辑软件", size: 34, weight: .semibold, color: NSColor(white: 0.92, alpha: 1), at: NSPoint(x: 456, y: 330))
text("A vlog editor built for Apple silicon Macs", size: 26, weight: .medium, color: NSColor(white: 0.62, alpha: 1), at: NSPoint(x: 456, y: 284))

// 卖点标签
var x: CGFloat = 456
for label in ["免费 Free", "无水印 No watermark", "本地运行 On-device", "2.3 MB"] {
    let attr = NSAttributedString(string: label, attributes: [.font: NSFont.systemFont(ofSize: 22, weight: .semibold), .foregroundColor: accent])
    let w = attr.size().width + 32
    let pill = NSBezierPath(roundedRect: NSRect(x: x, y: 190, width: w, height: 44), xRadius: 22, yRadius: 22)
    accent.withAlphaComponent(0.14).setFill(); pill.fill()
    accent.withAlphaComponent(0.5).setStroke(); pill.lineWidth = 1.5; pill.stroke()
    attr.draw(at: NSPoint(x: x + 16, y: 200))
    x += w + 14
}
text("Media Engine · Metal GPU · Neural Engine · HDR", size: 22, weight: .medium, color: NSColor(white: 0.5, alpha: 1), at: NSPoint(x: 456, y: 130))

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: out)
print("→ \(out.path)")
