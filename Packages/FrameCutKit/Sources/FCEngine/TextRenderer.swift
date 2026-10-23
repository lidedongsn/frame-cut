import CoreImage
import FCCore

/// 把一段文字按它的样式、位置和动画画到画布坐标上（原点在左下）。预览与导出共用。
public enum TextRenderer {
    /// t 时刻的文字图层；完全透明或没有文字时为 nil。
    public static func render(_ clip: TextClip, at t: Time, canvas: CGSize) -> CIImage? {
        let look = clip.appearance(at: t)
        guard look.opacity > 0.001, look.visibleCharacters != 0,
              let image = SubtitleRenderer.image(text: clip.text, style: clip.style, canvas: canvas, visibleCharacters: look.visibleCharacters)
        else { return nil }
        let rect = frame(of: image.extent.size, clip: clip, canvas: canvas)
        // 左上角原点 → Core Image 左下角原点
        var placed = image.transformed(by: CGAffineTransform(translationX: rect.minX.rounded(), y: (canvas.height - rect.maxY).rounded()))
        if look.scale != 1 {
            let c = CGPoint(x: placed.extent.midX, y: placed.extent.midY)
            placed = placed.transformed(by: CGAffineTransform(translationX: -c.x, y: -c.y)
                .concatenating(CGAffineTransform(scaleX: look.scale, y: look.scale))
                .concatenating(CGAffineTransform(translationX: c.x, y: c.y)))
        }
        if look.offsetY != 0 {
            placed = placed.transformed(by: CGAffineTransform(translationX: 0, y: -look.offsetY * canvas.height))
        }
        if look.opacity < 1 {
            let o = CGFloat(look.opacity)
            placed = placed.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: o, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: o, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: o, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: o),
            ])
        }
        return placed
    }

    /// 文字在画布上的位置（左上角为原点，未加动画）。预览上的选框也用它。
    public static func frame(of size: CGSize, clip: TextClip, canvas: CGSize) -> CGRect {
        clip.style.frame(textSize: size, canvas: canvas)
    }

    /// 完整文字（不加动画）在画布上的位置；没有文字时为 nil。
    public static func frame(of clip: TextClip, canvas: CGSize) -> CGRect? {
        SubtitleRenderer.image(text: clip.text, style: clip.style, canvas: canvas).map { frame(of: $0.extent.size, clip: clip, canvas: canvas) }
    }
}
