import SwiftUI

/// 深色主题，单一青色强调色。
enum Theme {
    static let window = Color(red: 0.067, green: 0.067, blue: 0.078)
    static let panel = Color(red: 0.102, green: 0.102, blue: 0.118)
    static let raised = Color(red: 0.145, green: 0.145, blue: 0.165)
    static let hover = Color(red: 0.19, green: 0.19, blue: 0.215)
    static let border = Color.white.opacity(0.07)
    static let accent = Color(red: 0.16, green: 0.82, blue: 0.86)
    static let text = Color.white.opacity(0.92)
    static let secondary = Color.white.opacity(0.55)
    static let tertiary = Color.white.opacity(0.32)

    static let videoClip = Color(red: 0.17, green: 0.30, blue: 0.40)
    static let musicClip = Color(red: 0.14, green: 0.34, blue: 0.27)
    static let subtitleClip = Color(red: 0.40, green: 0.29, blue: 0.14)
    static let textClip = Color(red: 0.36, green: 0.22, blue: 0.42)
    static let duckRange = Color(red: 0.55, green: 0.36, blue: 0.12)
    static let playhead = Color(red: 1.0, green: 0.85, blue: 0.25)

    static let corner: CGFloat = 6
}

/// 面板小标题。
struct SectionTitle: View {
    let text: LocalizedStringKey
    init(_ text: LocalizedStringKey) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Theme.secondary)
            .textCase(nil)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 带标签与数值的滑块，拖动期间合并为一次撤销。
struct LabeledSlider: View {
    let title: LocalizedStringKey
    @Binding var value: Double
    let range: ClosedRange<Double>
    var format: (Double) -> String = { String(format: "%.0f", $0 * 100) }
    var onEditing: (Bool) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.system(size: 12)).foregroundStyle(Theme.text)
                Spacer()
                Text(format(value)).font(.system(size: 11).monospacedDigit()).foregroundStyle(Theme.secondary)
            }
            Slider(value: $value, in: range, onEditingChanged: onEditing)
                .controlSize(.small)
                .tint(Theme.accent)
        }
    }
}

struct PanelButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .foregroundStyle(prominent ? Color.black : Theme.text)
            .background(
                RoundedRectangle(cornerRadius: Theme.corner)
                    .fill(prominent ? Theme.accent : Theme.raised)
                    .opacity(configuration.isPressed ? 0.7 : 1)
            )
    }
}

extension View {
    /// SF Symbols 的部分图标（如 textformat）在中文环境下会换成汉字版本，图标统一用拉丁字母版本。
    func latinSymbol() -> some View { environment(\.locale, Locale(identifier: "en")) }

    func panelBackground() -> some View {
        background(Theme.panel).overlay(Rectangle().stroke(Theme.border, lineWidth: 1))
    }
}
