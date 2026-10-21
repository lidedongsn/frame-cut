import FCCore
import FCEngine
import SwiftUI

/// 预览画面上直接调整字幕：拖动移动位置，拖角或双指捏合缩放字号，点击选中。
/// 样式对全部字幕生效；暂停时可操作，播放时不响应。
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

    /// 当前显示的字幕（重叠时多条），与渲染用同一个排版。
    private var lines: (subs: [Subtitle], rect: CGRect)? {
        let t = model.playhead
        let subs = model.project.subtitles.filter { $0.start <= t && t < $0.end }.sorted { $0.start < $1.start }
        let rects = SubtitleRenderer.layout(subs, style: style, canvas: canvas).map(\.rect)
        guard let first = rects.first else { return nil }
        return (subs, rects.dropFirst().reduce(first) { $0.union($1) })
    }

    var body: some View {
        if !model.isPlaying, !model.comparingOriginal, let (subs, rect) = lines, let sub = subs.last {
            let selected = subs.contains { model.selection == .subtitle($0.id) }
            let active = hovering || dragStart != nil || resizeStart != nil || selected
            ZStack(alignment: .topLeading) {
                if snapped {
                    Rectangle().fill(Theme.accent).frame(width: 1, height: canvas.height)
                        .offset(x: canvas.width / 2)
                }
                // 框和右下角手柄放在同一个容器里跟踪悬停，移到手柄上时手柄不会消失
                ZStack(alignment: .bottomTrailing) {
                    // 平时不画框，鼠标移上去或选中时才显示，不干扰看画面
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(active ? Theme.accent : Color.clear, lineWidth: 1)
                        .contentShape(Rectangle())
                        .frame(width: rect.width + 8, height: rect.height + 8)
                        .onTapGesture { model.selection = .subtitle(sub.id) }
                        .gesture(moveGesture(sub))
                        .simultaneousGesture(pinchGesture)
                        .help("拖动调整位置，拖右下角或双指捏合调整大小（对全部字幕生效）")
                    Circle().fill(Theme.accent)
                        .overlay(Circle().stroke(.white, lineWidth: 1))
                        .frame(width: 10, height: 10)
                        .opacity(active ? 1 : 0)
                        .contentShape(Rectangle().inset(by: -6))
                        .offset(x: 5, y: 5)
                        .gesture(resizeGesture(rect))
                }
                .onHover { hovering = $0 }
                .offset(x: rect.minX - 4, y: rect.minY - 4)
            }
            .frame(width: canvas.width, height: canvas.height, alignment: .topLeading)
            .onDisappear { hovering = false }
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
