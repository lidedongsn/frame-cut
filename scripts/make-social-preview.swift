// 生成仓库分享图（1280×640，GitHub Social preview / README 横幅）。
// 用法：swift scripts/make-social-preview.swift App/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png docs/images/social-preview.png
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

func attributed(_ s: String, size: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSAttributedString {
    NSAttributedString(string: s, attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color])
}
let accent = NSColor(srgbRed: 0.16, green: 0.82, blue: 0.86, alpha: 1)
let title = attributed("FrameCut", size: 92, weight: .heavy, color: .white)
let subtitle = attributed("为 Apple 芯片 Mac 打造的 vlog 剪辑软件", size: 34, weight: .semibold, color: NSColor(white: 0.92, alpha: 1))
let english = attributed("A vlog editor built for Apple silicon Macs", size: 26, weight: .medium, color: NSColor(white: 0.62, alpha: 1))
let tech = attributed("Media Engine · Metal GPU · Neural Engine · HDR", size: 22, weight: .medium, color: NSColor(white: 0.5, alpha: 1))
let tags = ["免费 Free", "无水印 No watermark", "本地运行 On-device", "开源 Open source"]
    .map { attributed($0, size: 20, weight: .semibold, color: accent) }
let tagPad: CGFloat = 14, tagGap: CGFloat = 10, tagHeight: CGFloat = 42
let tagsWidth = tags.reduce(0) { $0 + $1.size().width + tagPad * 2 } + tagGap * CGFloat(tags.count - 1)

// 整体（图标 + 文字块）在画布上水平、垂直居中
let iconSize: CGFloat = 300, gap: CGFloat = 56
let textWidth = max(title.size().width, subtitle.size().width, english.size().width, tech.size().width, tagsWidth)
// 文字块自上而下：标题、中文、英文、标签、技术说明（行距按视觉调过）
let lines: [CGFloat] = [title.size().height, 14, subtitle.size().height, 6, english.size().height, 30, tagHeight, 28, tech.size().height]
let textHeight = lines.reduce(0, +)
let blockWidth = iconSize + gap + textWidth
let left = (CGFloat(W) - blockWidth) / 2
let top = (CGFloat(H) + textHeight) / 2   // 文字块顶边（AppKit 原点在左下）

icon.draw(in: NSRect(x: left - 20, y: (CGFloat(H) - iconSize) / 2 - 20, width: iconSize + 40, height: iconSize + 40))

let tx = left + iconSize + gap
var y = top
func place(_ a: NSAttributedString, spacingAfter: CGFloat) {
    y -= a.size().height
    a.draw(at: NSPoint(x: tx, y: y))
    y -= spacingAfter
}
place(title, spacingAfter: 14)
place(subtitle, spacingAfter: 6)
place(english, spacingAfter: 30)
y -= tagHeight
var x = tx
for tag in tags {
    let w = tag.size().width + tagPad * 2
    let pill = NSBezierPath(roundedRect: NSRect(x: x, y: y, width: w, height: tagHeight), xRadius: tagHeight / 2, yRadius: tagHeight / 2)
    accent.withAlphaComponent(0.14).setFill(); pill.fill()
    accent.withAlphaComponent(0.5).setStroke(); pill.lineWidth = 1.5; pill.stroke()
    tag.draw(at: NSPoint(x: x + tagPad, y: y + (tagHeight - tag.size().height) / 2))
    x += w + tagGap
}
y -= 28
place(tech, spacingAfter: 0)
print("左右边距 \(Int(left)) / \(Int(CGFloat(W) - left - blockWidth))，上下边距 \(Int(CGFloat(H) - top)) / \(Int(y))")

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: out)
print("→ \(out.path)")
