import FCCore
import SwiftUI

/// 在预览画面上原地编辑文字或字幕：盖在原文字上，字体、字号、颜色与画面一致。
/// 回车、Esc 或点别处结束；整次编辑是一步撤销（见 EditorModel.beginPreviewEditing）。
struct PreviewTextEditor: View {
    @Bindable var model: EditorModel
    let text: Binding<String>
    let style: SubtitleStyle
    /// 文字在画布上的位置（随输入实时变化）。
    let rect: CGRect
    let canvas: CGSize

    @FocusState private var focused: Bool

    var body: some View {
        // 字号与渲染一致，但太小时放大到看得清
        let size = max(13, style.fontSize * canvas.height)
        let width = min(canvas.width, max(rect.width, size * 4) + 24)
        TextField("", text: text, axis: .vertical)
            .textFieldStyle(.plain)
            .font(.custom(style.fontName, size: size))
            .foregroundStyle(Color(red: style.textColor.r, green: style.textColor.g, blue: style.textColor.b))
            .multilineTextAlignment(.center)
            .focused($focused)
            .onSubmit { model.endPreviewEditing() }
            .onExitCommand { model.endPreviewEditing() }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .frame(width: width)
            .background(Color.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.accent, lineWidth: 1))
            .help("回车完成，⌥回车换行")
            .position(x: min(max(width / 2, rect.midX), canvas.width - width / 2), y: rect.midY)
            .onAppear { focused = true }
            .onChange(of: focused) { _, now in if !now { model.endPreviewEditing() } }
            .onDisappear { model.endPreviewEditing() }
            // 点了时间线等不抢焦点的地方时，按选中变化结束编辑
            .onChange(of: model.selection) { model.endPreviewEditing() }
    }
}
