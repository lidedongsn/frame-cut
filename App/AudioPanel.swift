import FCCore
import SwiftUI

// MARK: - 整条音频轨

/// 选中音频片段时，调整它所在的整条音频轨。
struct AudioLaneSection: View {
    @Bindable var model: EditorModel
    let lane: Int

    private func binding<T>(_ kp: WritableKeyPath<AudioLaneSettings, T>) -> Binding<T> {
        Binding(
            get: { model.project.laneSettings(lane)[keyPath: kp] },
            set: { v in model.store.perform { $0.updateAudioLane(lane) { $0[keyPath: kp] = v } } }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("音频轨 \(lane + 1)（整条轨）")
            Toggle("整条轨静音", isOn: binding(\.muted)).font(.system(size: 12))
            LabeledSlider(title: "轨道音量", value: binding(\.volume), range: 0...2,
                          format: { "\(Int($0 * 100))%" }, onEditing: model.coalesce)
        }
    }
}

// MARK: - 人声避让

/// 人声避让设置：开关（对这段音频）、调低幅度与渐变（对所有开启避让的音频）、生成 / 添加人声区间。
struct DuckingSection: View {
    @Bindable var model: EditorModel
    /// 选中的音频片段；选中人声区间时为 nil。
    let clipID: UUID?

    private func duck(_ kp: WritableKeyPath<DuckSettings, Double>) -> Binding<Double> {
        model.projectBinding((\Project.duck).appending(path: kp))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("人声避让")
            if let clipID {
                Toggle("有人声时调低这段音频", isOn: model.musicBinding(clipID, \.ducks, default: false))
                    .font(.system(size: 12))
            }
            LabeledSlider(title: "调低到", value: duck(\.level), range: DuckSettings.levelRange,
                          format: { "\(Int($0 * 100))%" }, onEditing: model.coalesce)
            LabeledSlider(title: "渐变", value: duck(\.fade), range: DuckSettings.fadeRange,
                          format: { String(format: String(localized: "%.1f 秒"), $0) }, onEditing: model.coalesce)
            Text(model.project.duckRanges.isEmpty
                 ? "还没有人声区间。可以按字幕或声音生成，再在时间线「人声」行里拖动调整；也可以手动添加。"
                 : "共 \(model.project.duckRanges.count) 个人声区间，在时间线「人声」行里拖动、拖两端调整，右键删除。")
                .font(.system(size: 11)).foregroundStyle(Theme.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Button("按字幕生成") { model.generateDuckRanges(fromSubtitles: true, enableFor: clipID) }
                    .disabled(model.project.subtitles.isEmpty)
                    .help(model.project.subtitles.isEmpty ? "还没有字幕" : "用字幕的时间作为人声区间（最准）")
                Button("按声音检测") { model.generateDuckRanges(fromSubtitles: false, enableFor: clipID) }
                    .disabled(model.generatingDuckRanges)
                    .help("检测视频原声和未开启避让的音频（如旁白）里的说话声。风声、音乐也可能被当成人声，生成后请检查。")
            }
            .buttonStyle(PanelButtonStyle())
            HStack(spacing: 6) {
                Button("在播放头处添加") { model.addDuckRangeAtPlayhead() }
                Button("清空") { model.store.perform { $0.replaceDuckRanges([]) } }
                    .disabled(model.project.duckRanges.isEmpty)
            }
            .buttonStyle(PanelButtonStyle())
            if model.generatingDuckRanges {
                ProgressView().controlSize(.small)
            }
        }
    }
}

/// 选中人声区间时的检查器。
struct DuckRangeInspector: View {
    @Bindable var model: EditorModel
    let id: UUID

    var body: some View {
        InspectorHeader(title: "人声区间", icon: "waveform.badge.minus")
        if let r = model.project.duckRanges.first(where: { $0.id == id }) {
            Text("\(r.start.displayString) – \(r.end.displayString)")
                .font(.system(size: 11).monospacedDigit()).foregroundStyle(Theme.secondary)
        }
        Text("在这段时间里，开启了「有人声时调低」的音频会自动调低。")
            .font(.system(size: 11)).foregroundStyle(Theme.tertiary)
            .fixedSize(horizontal: false, vertical: true)
        Button("删除这个区间", role: .destructive) { model.deleteSelection() }
            .buttonStyle(PanelButtonStyle())
        Divider().overlay(Theme.border)
        DuckingSection(model: model, clipID: nil)
    }
}

// MARK: - 录音

/// 录旁白按钮：未录音时开始，录音中停止。
struct RecordButton: View {
    @Bindable var model: EditorModel

    var body: some View {
        Button {
            if model.isRecording { model.stopRecording() } else { model.startRecording() }
        } label: {
            Label(model.isRecording ? "停止录音" : "录制旁白", systemImage: model.isRecording ? "stop.fill" : "mic.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(PanelButtonStyle())
        .disabled(model.project.mainTrack.isEmpty && !model.isRecording)
        .help("从播放头开始边放画面边录音，录好后自动放到音频轨上；按空格停止。录音时画面静音。")
    }
}

/// 预览画面上的录音提示。
struct RecordingBadge: View {
    let began: Date

    var body: some View {
        SwiftUI.TimelineView(.periodic(from: began, by: 0.5)) { context in
            let seconds = Int(context.date.timeIntervalSince(began))
            HStack(spacing: 6) {
                Circle().fill(Color.red).frame(width: 8, height: 8)
                Text(String(format: String(localized: "正在录音 %02d:%02d · 按空格停止"), seconds / 60, seconds % 60))
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
            }
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Color.black.opacity(0.7), in: Capsule())
            .foregroundStyle(.white)
        }
    }
}
