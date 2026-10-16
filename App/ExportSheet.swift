import AppKit
import FCCore
import FCEngine
import SwiftUI

/// 导出设置与进度。
struct ExportSheet: View {
    @Bindable var model: EditorModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("export.shortSide") private var shortSide = 1080
    @AppStorage("export.frameRate") private var frameRate = 30
    @AppStorage("export.codec") private var codecRaw = ExportSettings.Codec.h264.rawValue

    private var settings: ExportSettings {
        ExportSettings(shortSide: shortSide, frameRate: frameRate, codec: ExportSettings.Codec(rawValue: codecRaw) ?? .h264)
    }

    private var outputSize: CGSize { RenderSize.size(aspect: model.project.aspect, shortSide: shortSide) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("导出视频").font(.title3.weight(.semibold))
            switch model.exportState {
            case .idle, .failed:
                form
            case .running(let p):
                VStack(alignment: .leading, spacing: 10) {
                    Text("正在导出… \(Int(p * 100))%").monospacedDigit()
                    ProgressView(value: p).tint(Theme.accent)
                    HStack {
                        Spacer()
                        Button("取消导出", role: .cancel) { model.cancelExport() }
                    }
                }
            case .done(let url):
                VStack(alignment: .leading, spacing: 12) {
                    Label("导出完成", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    Text(url.path).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2).truncationMode(.middle)
                    HStack {
                        Button("在 Finder 中显示") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                        Button("播放") { NSWorkspace.shared.open(url) }
                        Spacer()
                        Button("完成") {
                            model.exportState = .idle
                            dismiss()
                        }
                        .keyboardShortcut(.defaultAction)
                    }
                }
            }
        }
        .padding(22)
        .frame(width: 440)
    }

    @ViewBuilder
    private var form: some View {
        Form {
            Picker("分辨率", selection: $shortSide) {
                Text("720p").tag(720)
                Text("1080p").tag(1080)
                Text("4K").tag(2160)
            }
            Picker("帧率", selection: $frameRate) {
                ForEach([24, 25, 30, 60], id: \.self) { Text("\($0) fps").tag($0) }
            }
            Picker("编码", selection: $codecRaw) {
                ForEach(ExportSettings.Codec.allCases, id: \.self) { Text($0.displayName).tag($0.rawValue) }
            }
        }
        .formStyle(.grouped)
        Text("输出 \(Int(outputSize.width))×\(Int(outputSize.height)) · 约 \(settings.bitrate(for: outputSize) / 1_000_000) Mbps · 时长 \(model.duration.displayString) · 无水印")
            .font(.system(size: 11)).foregroundStyle(.secondary)
        if case .failed(let message) = model.exportState {
            Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.system(size: 12))
        }
        HStack {
            Spacer()
            Button("取消") {
                model.exportState = .idle
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            Button("导出…") { chooseDestination() }
                .keyboardShortcut(.defaultAction)
                .disabled(model.duration == .zero)
        }
    }

    private func chooseDestination() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.nameFieldStringValue = model.project.name + ".mp4"
        panel.directoryURL = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.save()
        model.export(settings: settings, to: url)
    }
}
