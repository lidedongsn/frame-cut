import AppKit
import FCCore
import FCEngine
import SwiftUI

/// 导出：默认按素材推荐（分辨率不超过素材、帧率同工程、HDR 工程导出 HLG），一键导出；需要时展开高级设置。
struct ExportSheet: View {
    @Bindable var model: EditorModel
    @Environment(\.dismiss) private var dismiss
    @State private var settings = ExportSettings()
    @State private var showAdvanced = false
    @AppStorage("export.burnSubtitles") private var burnSubtitles = true
    @AppStorage("export.writeSRT") private var writeSRT = false

    private var isHDRProject: Bool { model.project.colorMode == .hdr }
    private var outputSize: CGSize { RenderSize.size(aspect: model.project.aspect, shortSide: settings.shortSide) }

    private var resolutionName: String {
        switch settings.shortSide {
        case 720: "720p"
        case 2160: "4K"
        default: "1080p"
        }
    }

    private var summary: String {
        var parts = [resolutionName, "\(settings.frameRate) fps"]
        parts.append(settings.dynamicRange == .sdr ? "SDR" : settings.dynamicRange.displayName)
        parts.append(settings.effectiveCodec == .h264 ? "H.264" : "HEVC")
        return parts.joined(separator: " · ")
    }

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
        .onAppear { settings = ExportSettings.recommended(for: model.project) }
    }

    @ViewBuilder
    private var form: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(summary).font(.system(size: 15, weight: .semibold)).monospacedDigit()
            Text("输出 \(Int(outputSize.width))×\(Int(outputSize.height)) · 约 \(settings.bitrate(for: outputSize) / 1_000_000) Mbps · 时长 \(model.duration.displayString) · 无水印")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            Text("已按素材自动选择，一般直接导出即可。").font(.system(size: 11)).foregroundStyle(.secondary)
        }
        if !model.project.subtitles.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Toggle("字幕画进视频", isOn: $burnSubtitles)
                Toggle("同时导出 .srt 字幕文件（与视频同名）", isOn: $writeSRT)
            }
            .toggleStyle(.checkbox)
            .font(.system(size: 12))
        }
        DisclosureGroup("高级设置", isExpanded: $showAdvanced) {
            Form {
                Picker("分辨率", selection: $settings.shortSide) {
                    Text("720p").tag(720)
                    Text("1080p").tag(1080)
                    Text("4K").tag(2160)
                }
                Picker("帧率", selection: $settings.frameRate) {
                    ForEach(Project.frameRates, id: \.self) { Text("\($0) fps").tag($0) }
                }
                if isHDRProject {
                    Picker("动态范围", selection: $settings.dynamicRange) {
                        Text("HDR（HLG，推荐）").tag(DynamicRangeOutput.hlg)
                        Text("HDR10（PQ）").tag(DynamicRangeOutput.pq)
                        Text("SDR（自动色调映射）").tag(DynamicRangeOutput.sdr)
                    }
                }
                if settings.dynamicRange.isHDR {
                    LabeledContent("编码", value: "HEVC 10 位（HDR 必需）")
                } else {
                    Picker("编码", selection: $settings.codec) {
                        ForEach(ExportSettings.Codec.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                }
            }
            .formStyle(.grouped)
            if isHDRProject {
                Text(rangeHint).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Button("恢复推荐设置") { settings = ExportSettings.recommended(for: model.project) }
                .buttonStyle(.link).font(.system(size: 11))
        }
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

    private var rangeHint: String {
        switch settings.dynamicRange {
        case .hlg: "兼容性最好的 HDR 格式：iPhone、抖音、B 站、YouTube 都支持，在普通屏幕上也能正常显示。"
        case .pq: "HDR10：适合电视和专业平台，带 1000 尼特 HDR10 元数据。普通屏幕上依赖播放器做色调映射。"
        case .sdr: "转为普通视频：高光平滑压缩，不会过曝，适合不支持 HDR 的平台。"
        }
    }

    private func chooseDestination() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.nameFieldStringValue = model.project.name + ".mp4"
        panel.directoryURL = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.save()
        let hasSubs = !model.project.subtitles.isEmpty
        model.export(settings: settings, to: url, burnSubtitles: !hasSubs || burnSubtitles, writeSRT: hasSubs && writeSRT)
    }
}
