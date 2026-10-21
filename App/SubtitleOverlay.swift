import FCCore
import FCEngine
import SwiftUI

/// 预览画面上直接调整字幕：拖动移动位置，拖角或双指捏合缩放字号，点击选中。
/// 样式对全部字幕生效；暂停时显示，播放时隐藏不挡画面。
struct SubtitleOverlay: View {
    @Bindable var model: EditorModel
    let canvas: CGSize

    @State private var dragStart: SubtitleStyle?
    @State private var resizeStart: (style: SubtitleStyle, distance: CGFloat)?
    @State private var pinchStart: Double?
    @State private var snapped = false
    @State private var hovering = false

    /// 吸附到水平居中的距离（点）。
    private let snapDistance: CGFloat = 8

    private var style: SubtitleStyle { model.project.subtitleStyle }

    private var subtitle: Subtitle? {
        let t = model.playhead
        return model.project.subtitles.filter { $0.start <= t && t < $0.end }.max { $0.start < $1.start }
    }

    var body: some View {
        if !model.isPlaying, !model.comparingOriginal, let sub = subtitle,
           let image = SubtitleRenderer.image(text: sub.text, style: style, canvas: canvas) {
            let rect = style.frame(textSize: image.extent.size, canvas: canvas)
            let active = hovering || dragStart != nil || resizeStart != nil || model.selection == .subtitle(sub.id)
            ZStack(alignment: .topLeading) {
                if snapped {
                    Rectangle().fill(Theme.accent).frame(width: 1, height: canvas.height)
                        .offset(x: canvas.width / 2)
                }
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(active ? Theme.accent : Color.white.opacity(0.35),
                                  style: StrokeStyle(lineWidth: 1, dash: active ? [] : [4, 3]))
                    .contentShape(Rectangle())
                    .frame(width: rect.width + 8, height: rect.height + 8)
                    .offset(x: rect.minX - 4, y: rect.minY - 4)
                    .onHover { hovering = $0 }
                    .onTapGesture { model.selection = .subtitle(sub.id) }
                    .gesture(moveGesture(sub))
                    .simultaneousGesture(pinchGesture)
                    .help("拖动调整位置，拖右下角或双指捏合调整大小（对全部字幕生效）")
                if active {
                    Circle().fill(Theme.accent)
                        .overlay(Circle().stroke(.white, lineWidth: 1))
                        .frame(width: 10, height: 10)
                        .contentShape(Rectangle().inset(by: -6))
                        .offset(x: rect.maxX + 4 - 5, y: rect.maxY + 4 - 5)
                        .gesture(resizeGesture(rect))
                }
            }
            .frame(width: canvas.width, height: canvas.height, alignment: .topLeading)
        }
    }

    private func moveGesture(_ sub: Subtitle) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { v in
                if dragStart == nil {
                    dragStart = style
                    model.selection = .subtitle(sub.id)
                    model.store.beginCoalescing()
                }
                guard let start = dragStart else { return }
                var x = start.horizontalPosition * canvas.width + v.translation.width
                let y = start.verticalPosition * canvas.height + v.translation.height
                snapped = abs(x - canvas.width / 2) < snapDistance
                if snapped { x = canvas.width / 2 }
                model.store.perform {
                    $0.subtitleStyle.horizontalPosition = min(1, max(0, x / canvas.width))
                    $0.subtitleStyle.verticalPosition = min(1, max(0, y / canvas.height))
                }
            }
            .onEnded { _ in
                dragStart = nil
                snapped = false
                model.store.endCoalescing()
            }
    }

    /// 拖角缩放：按手指到字幕中心的距离变化等比缩放字号。
    private func resizeGesture(_ rect: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named("subtitleCanvas"))
            .onChanged { v in
                let center = CGPoint(x: rect.midX, y: rect.midY)
                func distance(_ p: CGPoint) -> CGFloat { max(1, hypot(p.x - center.x, p.y - center.y)) }
                if resizeStart == nil {
                    resizeStart = (style, distance(v.startLocation))
                    model.store.beginCoalescing()
                }
                guard let start = resizeStart else { return }
                let size = start.style.fontSize * Double(distance(v.location) / start.distance)
                model.store.perform { $0.subtitleStyle.fontSize = size.clamped(to: SubtitleStyle.fontSizeRange) }
            }
            .onEnded { _ in
                resizeStart = nil
                model.store.endCoalescing()
            }
    }

    private var pinchGesture: some Gesture {
        MagnifyGesture()
            .onChanged { v in
                if pinchStart == nil {
                    pinchStart = style.fontSize
                    model.store.beginCoalescing()
                }
                guard let start = pinchStart else { return }
                model.store.perform { $0.subtitleStyle.fontSize = (start * v.magnification).clamped(to: SubtitleStyle.fontSizeRange) }
            }
            .onEnded { _ in
                pinchStart = nil
                model.store.endCoalescing()
            }
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double { Swift.min(range.upperBound, Swift.max(range.lowerBound, self)) }
}
