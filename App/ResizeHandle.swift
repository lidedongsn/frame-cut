import AppKit
import SwiftUI

/// 面板之间的拖动分隔条：拖动改变相邻面板的宽度（或高度），并显示调整大小的光标。
struct ResizeHandle: View {
    enum Axis { case horizontal, vertical }

    let axis: Axis
    @Binding var value: Double
    let range: ClosedRange<Double>
    /// 为 true 时向右 / 向下拖动使数值变小（右侧面板、下方时间线）。
    var inverted = false

    @State private var start: Double?
    @State private var hovering = false

    var body: some View {
        Rectangle()
            .fill(hovering || start != nil ? Theme.accent.opacity(0.5) : Theme.border)
            .frame(width: axis == .horizontal ? 1 : nil, height: axis == .vertical ? 1 : nil)
            .padding(axis == .horizontal ? .horizontal : .vertical, 3)
            .contentShape(Rectangle())
            .onHover { inside in
                hovering = inside
                let cursor: NSCursor = axis == .horizontal ? .resizeLeftRight : .resizeUpDown
                if inside { cursor.push() } else { NSCursor.pop() }
            }
            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { g in
                    if start == nil { start = value }
                    let delta = Double(axis == .horizontal ? g.translation.width : g.translation.height)
                    value = min(range.upperBound, max(range.lowerBound, (start ?? value) + (inverted ? -delta : delta)))
                }
                .onEnded { _ in start = nil })
            .padding(axis == .horizontal ? .horizontal : .vertical, -3)
            .zIndex(1)
    }
}
