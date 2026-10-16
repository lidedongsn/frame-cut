import AppKit
import FCCore
import SwiftUI

/// 字幕：自动识别、逐条校对、全局样式。
struct SubtitlePanel: View {
    @Bindable var model: EditorModel
    @State private var confirmReplace = false
    @State private var showStyle = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button {
                    if model.project.subtitles.isEmpty { model.transcribe() } else { confirmReplace = true }
                } label: {
                    Label("识别字幕", systemImage: "waveform").frame(maxWidth: .infinity)
                }
                .buttonStyle(PanelButtonStyle(prominent: true))
                .disabled(model.project.mainTrack.isEmpty || isRunning)
                .help("用本地语音识别为主轨原声生成字幕（免费、离线）")

                Button {
                    let id = model.store.project.subtitles.isEmpty ? nil : UUID()
                    _ = id
                    var newID: UUID?
                    let at = model.playhead
                    model.store.perform { newID = $0.addSubtitle(at: at, text: "输入字幕") }
                    if let newID { model.selection = .subtitle(newID) }
                } label: {
                    Label("添加", systemImage: "plus")
                }
                .buttonStyle(PanelButtonStyle())
                .help("在播放头位置添加一条字幕")
            }

            statusView

            DisclosureGroup(isExpanded: $showStyle) {
                StyleEditor(model: model).padding(.top, 8)
            } label: {
                Text("字幕样式").font(.system(size: 12, weight: .medium))
            }
            .tint(Theme.secondary)

            Divider().overlay(Theme.border)

            if model.project.subtitles.isEmpty {
                Spacer()
                Text("还没有字幕。\n点击「识别字幕」自动生成，\n或「添加」手动输入。")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.tertiary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                Text("共 \(model.project.subtitles.count) 条 · 点击时间跳转，直接修改文字")
                    .font(.system(size: 11)).foregroundStyle(Theme.tertiary)
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(model.project.subtitles) { sub in
                                SubtitleRow(model: model, sub: sub)
                                    .id(sub.id)
                            }
                        }
                    }
                    .onChange(of: model.selection) { _, sel in
                        if case .subtitle(let id) = sel { withAnimation { proxy.scrollTo(id, anchor: .center) } }
                    }
                }
            }
        }
        .padding(10)
        .foregroundStyle(Theme.text)
        .confirmationDialog("替换现有字幕？", isPresented: $confirmReplace) {
            Button("重新识别并替换", role: .destructive) { model.transcribe() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("识别结果会替换当前的 \(model.project.subtitles.count) 条字幕（可撤销）。")
        }
    }

    private var isRunning: Bool {
        if case .running = model.transcribeState { return true }
        return false
    }

    @ViewBuilder
    private var statusView: some View {
        switch model.transcribeState {
        case .running(let message, let progress):
            VStack(alignment: .leading, spacing: 4) {
                Text(message).font(.system(size: 11)).foregroundStyle(Theme.secondary)
                if let progress {
                    ProgressView(value: progress).tint(Theme.accent)
                } else {
                    ProgressView().progressViewStyle(.linear).tint(Theme.accent)
                }
            }
        case .failed(let message):
            HStack {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(message).font(.system(size: 11)).foregroundStyle(Theme.secondary)
                Spacer()
                Button("关闭") { model.transcribeState = .idle }.buttonStyle(.plain).font(.system(size: 11))
            }
        case .idle:
            EmptyView()
        }
    }
}

private struct SubtitleRow: View {
    @Bindable var model: EditorModel
    let sub: Subtitle

    private var selected: Bool { model.selection == .subtitle(sub.id) }
    private var active: Bool { sub.start <= model.playhead && model.playhead < sub.end }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button {
                model.selection = .subtitle(sub.id)
                model.seek(to: sub.start)
            } label: {
                Text(sub.start.displayString)
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(active ? Theme.accent : Theme.tertiary)
                    .frame(width: 54, alignment: .leading)
                    .padding(.top, 3)
            }
            .buttonStyle(.plain)
            TextField("", text: model.subtitleBinding(sub.id, \.text, default: ""), axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .lineLimit(1...3)
            Button {
                model.store.perform { $0.removeSubtitle(id: sub.id) }
            } label: {
                Image(systemName: "xmark").font(.system(size: 9))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.tertiary)
            .padding(.top, 3)
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 6).fill(selected ? Theme.hover : (active ? Theme.raised : Color.clear)))
    }
}

private struct StyleEditor: View {
    @Bindable var model: EditorModel

    private let fonts: [(String, String)] = [
        ("PingFangSC-Semibold", "苹方 粗"),
        ("PingFangSC-Regular", "苹方 常规"),
        ("STHeitiSC-Medium", "黑体"),
        ("STSongti-SC-Bold", "宋体 粗"),
        ("STKaitiSC-Bold", "楷体"),
        ("HiraginoSansGB-W6", "冬青黑体"),
    ]

    private func style<T>(_ kp: WritableKeyPath<SubtitleStyle, T>) -> Binding<T> {
        model.projectBinding((\Project.subtitleStyle).appending(path: kp))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("字体", selection: style(\.fontName)) {
                ForEach(fonts, id: \.0) { Text($0.1).tag($0.0) }
            }
            .font(.system(size: 12))
            LabeledSlider(title: "字号", value: style(\.fontSize), range: 0.03...0.12,
                          format: { "\(Int($0 * 1000))" }, onEditing: model.coalesce)
            LabeledSlider(title: "位置（距顶部）", value: style(\.verticalPosition), range: 0.1...0.95,
                          format: { "\(Int($0 * 100))%" }, onEditing: model.coalesce)
            LabeledSlider(title: "描边粗细", value: style(\.strokeWidth), range: 0...0.3,
                          format: { "\(Int($0 * 100))" }, onEditing: model.coalesce)
            HStack(spacing: 14) {
                ColorPicker("文字", selection: colorBinding(style(\.textColor)), supportsOpacity: false)
                ColorPicker("描边", selection: colorBinding(style(\.strokeColor)), supportsOpacity: false)
                ColorPicker("背景", selection: colorBinding(style(\.backgroundColor)), supportsOpacity: true)
            }
            .font(.system(size: 12))
            HStack(spacing: 6) {
                preset("经典白字", text: .white, stroke: .black, bg: .clear)
                preset("黄字", text: RGBA(r: 1, g: 0.86, b: 0.2), stroke: .black, bg: .clear)
                preset("黑底白字", text: .white, stroke: .clear, bg: RGBA(r: 0, g: 0, b: 0, a: 0.6), strokeWidth: 0)
            }
        }
    }

    private func preset(_ name: String, text: RGBA, stroke: RGBA, bg: RGBA, strokeWidth: Double = 0.12) -> some View {
        Button(name) {
            model.store.perform {
                $0.subtitleStyle.textColor = text
                $0.subtitleStyle.strokeColor = stroke
                $0.subtitleStyle.backgroundColor = bg
                $0.subtitleStyle.strokeWidth = strokeWidth
            }
        }
        .buttonStyle(PanelButtonStyle())
    }
}
