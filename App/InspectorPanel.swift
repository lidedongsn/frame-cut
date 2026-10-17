import AppKit
import FCCore
import SwiftUI

/// 右侧检查器：随选中对象变化。
struct InspectorPanel: View {
    @Bindable var model: EditorModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                switch model.selection {
                case .video(let id) where model.project.mainClip(id: id) != nil:
                    VideoInspector(model: model, id: id)
                case .music(let id) where model.project.music(id: id) != nil:
                    MusicInspector(model: model, id: id)
                case .transition(let id) where model.project.mainClip(id: id) != nil:
                    TransitionInspector(model: model, id: id)
                case .subtitle(let id) where model.project.subtitle(id: id) != nil:
                    SubtitleInspector(model: model, id: id)
                default:
                    ProjectInspector(model: model)
                }
            }
            .padding(14)
        }
        .background(Theme.panel)
        .overlay(alignment: .leading) { Rectangle().fill(Theme.border).frame(width: 1) }
        .foregroundStyle(Theme.text)
    }
}

private struct InspectorHeader: View {
    let title: String
    let icon: String

    var body: some View {
        Label(title, systemImage: icon)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.text)
    }
}

// MARK: - 工程

private struct ProjectInspector: View {
    @Bindable var model: EditorModel

    private var screenSupportsHDR: Bool {
        (NSScreen.main?.maximumPotentialExtendedDynamicRangeColorComponentValue ?? 1) > 1
    }

    private var colorModeHint: String {
        switch model.project.colorMode {
        case .hdr:
            let screen = screenSupportsHDR ? "当前屏幕支持 HDR 预览。" : "当前屏幕不支持 HDR，预览会自动压缩亮度，导出不受影响。"
            return "保留 HDR 素材的高光与色彩，可导出 HDR（HLG / HDR10）或 SDR。" + screen
        case .sdr:
            return model.project.hasHDRAssets ? "HDR 素材会自动做色调映射，高光平滑压缩而不过曝。" : "普通视频。导入 HDR 素材（如 iPhone 拍摄）时会自动切换为 HDR。"
        }
    }

    var body: some View {
        InspectorHeader(title: "工程设置", icon: "slider.horizontal.3")
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle("画面比例")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 6)], spacing: 6) {
                ForEach(AspectRatio.allCases, id: \.self) { aspect in
                    Button {
                        guard aspect != model.project.aspect else { return }
                        model.store.perform { $0.setAspect(aspect) }
                    } label: {
                        VStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 2)
                                .stroke(model.project.aspect == aspect ? Theme.accent : Theme.secondary, lineWidth: 1.5)
                                .frame(width: aspect.ratio >= 1 ? 26 : 26 * aspect.ratio, height: aspect.ratio >= 1 ? 26 / aspect.ratio : 26)
                                .frame(height: 30)
                            Text(aspect.displayName).font(.system(size: 11))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 6))
                        .foregroundStyle(model.project.aspect == aspect ? Theme.accent : Theme.text)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle("色彩")
            Picker("", selection: Binding(get: { model.project.colorMode },
                                          set: { mode in
                                              // 点已选中的那一项不算手动设置，避免关掉自动切换和产生空撤销
                                              guard mode != model.project.colorMode else { return }
                                              model.store.perform { $0.setColorMode(mode) }
                                          })) {
                Text("SDR").tag(ColorMode.sdr)
                Text("HDR").tag(ColorMode.hdr)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Text(colorModeHint).font(.system(size: 11)).foregroundStyle(Theme.tertiary).fixedSize(horizontal: false, vertical: true)
        }
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle("帧率（fps）")
            Picker("", selection: Binding(get: { model.project.frameRate },
                                          set: { fps in
                                              guard fps != model.project.frameRate else { return }
                                              model.store.perform { $0.setFrameRate(fps) }
                                          })) {
                ForEach(Project.frameRates, id: \.self) { Text("\($0)").tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle("统计")
            Text("片段 \(model.project.mainTrack.count) · 音乐 \(model.project.musicTrack.count) · 字幕 \(model.project.subtitles.count)")
                .font(.system(size: 12)).foregroundStyle(Theme.secondary)
            Text("总时长 \(model.duration.displayString)").font(.system(size: 12)).foregroundStyle(Theme.secondary)
        }
        Text("提示：在时间线上点选片段、音乐、字幕或转场，可在这里调整它们的属性。")
            .font(.system(size: 11)).foregroundStyle(Theme.tertiary)
    }
}

// MARK: - 视频片段

private struct VideoInspector: View {
    @Bindable var model: EditorModel
    let id: UUID

    private var clip: VideoClip? { model.project.mainClip(id: id) }
    private var asset: MediaAsset? { clip.flatMap { model.project.asset(id: $0.assetID) } }

    var body: some View {
        InspectorHeader(title: asset?.kind == .image ? "照片" : "视频", icon: asset?.kind == .image ? "photo" : "film")
        if let asset {
            Text(asset.name).font(.system(size: 11)).foregroundStyle(Theme.tertiary).lineLimit(1).truncationMode(.middle)
        }

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionTitle("画面")
                Button("重置") { model.store.perform { $0.updateMain(id: id) { $0.transform = ClipTransform() } } }
                    .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Theme.accent)
            }
            LabeledSlider(title: "缩放", value: model.clipBinding(id, \.transform.scale, default: 1), range: 0.5...3,
                          format: { "\(Int($0 * 100))%" }, onEditing: model.coalesce)
            LabeledSlider(title: "水平位置", value: model.clipBinding(id, \.transform.offsetX, default: 0), range: -1...1,
                          format: { String(format: "%.2f", $0) }, onEditing: model.coalesce)
            LabeledSlider(title: "垂直位置", value: model.clipBinding(id, \.transform.offsetY, default: 0), range: -1...1,
                          format: { String(format: "%.2f", $0) }, onEditing: model.coalesce)
            HStack {
                Text("旋转").font(.system(size: 12))
                Spacer()
                Button {
                    model.store.perform { $0.updateMain(id: id) { $0.transform.quarterTurns = ($0.transform.quarterTurns + 1) % 4 } }
                } label: {
                    Label("\((clip?.transform.quarterTurns ?? 0) * 90)°", systemImage: "rotate.right")
                }
                .buttonStyle(PanelButtonStyle())
            }
        }

        if asset?.kind == .video {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle("变速")
                LabeledSlider(title: "速度", value: Binding(
                    get: { clip?.speed ?? 1 },
                    set: { v in model.store.perform { $0.setSpeed(id: id, v) } }
                ), range: 0.25...4, format: { String(format: "%.2fx", $0) }, onEditing: model.coalesce)
                HStack(spacing: 6) {
                    ForEach([0.5, 1, 1.5, 2], id: \.self) { s in
                        Button(String(format: s == 1 ? "1x" : "%.1fx", s)) { model.store.perform { $0.setSpeed(id: id, s) } }
                            .buttonStyle(PanelButtonStyle(prominent: clip?.speed == s))
                    }
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle("原声")
                Toggle("静音", isOn: model.clipBinding(id, \.muted, default: false)).toggleStyle(.switch).controlSize(.small)
                LabeledSlider(title: "音量", value: model.clipBinding(id, \.volume, default: 1), range: 0...2,
                              format: { "\(Int($0 * 100))%" }, onEditing: model.coalesce)
                    .disabled(clip?.muted == true)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                SectionTitle("时长")
                LabeledSlider(title: "显示时长", value: Binding(
                    get: { clip?.sourceDuration.seconds ?? 3 },
                    set: { v in
                        guard let clip else { return }
                        model.store.perform { $0.trimMain(id: id, sourceIn: clip.sourceIn, sourceOut: clip.sourceIn + Time(seconds: v)) }
                    }
                ), range: 0.5...15, format: { String(format: "%.1f 秒", $0) }, onEditing: model.coalesce)
            }
        }

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionTitle("调节")
                Button("重置") {
                    model.store.perform { $0.updateMain(id: id) { c in
                        c.filter.brightness = 0; c.filter.contrast = 0; c.filter.saturation = 0; c.filter.temperature = 0
                    } }
                }
                .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Theme.accent)
            }
            Text("滤镜：\(clip?.filter.preset.displayName ?? "")（在左侧「滤镜」中选择）")
                .font(.system(size: 11)).foregroundStyle(Theme.tertiary)
            adjust("亮度", \.filter.brightness)
            adjust("对比度", \.filter.contrast)
            adjust("饱和度", \.filter.saturation)
            adjust("色温", \.filter.temperature)
        }
    }

    private func adjust(_ title: String, _ kp: WritableKeyPath<VideoClip, Double>) -> some View {
        LabeledSlider(title: title, value: model.clipBinding(id, kp, default: 0), range: -1...1,
                      format: { String(format: "%+.0f", $0 * 100) }, onEditing: model.coalesce)
    }
}

// MARK: - 音乐

private struct MusicInspector: View {
    @Bindable var model: EditorModel
    let id: UUID

    var body: some View {
        InspectorHeader(title: "音乐", icon: "music.note")
        if let clip = model.project.music(id: id), let asset = model.project.asset(id: clip.assetID) {
            Text(asset.name).font(.system(size: 11)).foregroundStyle(Theme.tertiary).lineLimit(1)
            Text("\(clip.start.displayString) – \(clip.end.displayString)").font(.system(size: 11).monospacedDigit()).foregroundStyle(Theme.secondary)
        }
        VStack(alignment: .leading, spacing: 10) {
            LabeledSlider(title: "音量", value: model.musicBinding(id, \.volume, default: 1), range: 0...2,
                          format: { "\(Int($0 * 100))%" }, onEditing: model.coalesce)
            LabeledSlider(title: "淡入", value: model.seconds(model.musicBinding(id, \.fadeIn, default: .zero)), range: 0...5,
                          format: { String(format: "%.1f 秒", $0) }, onEditing: model.coalesce)
            LabeledSlider(title: "淡出", value: model.seconds(model.musicBinding(id, \.fadeOut, default: .zero)), range: 0...5,
                          format: { String(format: "%.1f 秒", $0) }, onEditing: model.coalesce)
        }
        Text("在时间线上拖动音乐可调整位置，拖动两端可裁剪；⌘B 在播放头处分割。")
            .font(.system(size: 11)).foregroundStyle(Theme.tertiary)
    }
}

// MARK: - 转场

private struct TransitionInspector: View {
    @Bindable var model: EditorModel
    let id: UUID

    private var transition: FCCore.Transition? { model.project.transitions[id] }
    private var effective: Time? { model.layout.placement(for: id)?.transitionIn?.duration }

    var body: some View {
        InspectorHeader(title: "转场", icon: "square.split.diagonal")
        Picker("效果", selection: Binding<TransitionKind?>(
            get: { transition?.kind },
            set: { kind in
                model.store.perform { p in
                    p.setTransition(kind.map { FCCore.Transition(kind: $0, duration: transition?.duration ?? FCCore.Transition.defaultDuration) }, before: id)
                }
            }
        )) {
            Text("无").tag(TransitionKind?.none)
            ForEach(TransitionKind.allCases, id: \.self) { Text($0.displayName).tag(TransitionKind?.some($0)) }
        }
        if transition != nil {
            LabeledSlider(title: "时长", value: Binding(
                get: { transition?.duration.seconds ?? 0.5 },
                set: { v in model.store.perform { $0.transitions[id]?.duration = Time(seconds: v) } }
            ), range: 0.2...2, format: { String(format: "%.1f 秒", $0) }, onEditing: model.coalesce)
            if let effective, let transition, effective < transition.duration {
                Text("片段较短，实际转场时长为 \(String(format: "%.2f", effective.seconds)) 秒")
                    .font(.system(size: 11)).foregroundStyle(.orange)
            }
            Button("应用到全部交界") {
                if let transition { model.store.perform { $0.applyTransitionToAll(transition) } }
            }
            .buttonStyle(PanelButtonStyle())
        }
    }
}

// MARK: - 字幕

private struct SubtitleInspector: View {
    @Bindable var model: EditorModel
    let id: UUID

    var body: some View {
        InspectorHeader(title: "字幕", icon: "captions.bubble")
        TextField("字幕内容", text: model.subtitleBinding(id, \.text, default: ""), axis: .vertical)
            .textFieldStyle(.roundedBorder)
            .lineLimit(2...5)
        if let sub = model.project.subtitle(id: id) {
            Text("\(sub.start.displayString) – \(sub.end.displayString)")
                .font(.system(size: 11).monospacedDigit()).foregroundStyle(Theme.secondary)
        }
        Text("样式对全部字幕生效，在左侧「字幕」中调整。")
            .font(.system(size: 11)).foregroundStyle(Theme.tertiary)
        Button("删除这条字幕", role: .destructive) { model.deleteSelection() }
            .buttonStyle(PanelButtonStyle())
    }
}
