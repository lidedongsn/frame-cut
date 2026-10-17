import FCCore
import FCEngine
import FCMedia
import SwiftUI

enum LibraryTab: String, CaseIterable {
    case media, audio, text, transition, filter

    var title: String {
        switch self {
        case .media: "素材"
        case .audio: "音频"
        case .text: "字幕"
        case .transition: "转场"
        case .filter: "滤镜"
        }
    }

    var icon: String {
        switch self {
        case .media: "photo.on.rectangle"
        case .audio: "music.note"
        case .text: "captions.bubble"
        case .transition: "square.split.diagonal"
        case .filter: "camera.filters"
        }
    }
}

/// 左侧素材库：素材 / 音频 / 字幕 / 转场 / 滤镜。
struct LibraryPanel: View {
    @Bindable var model: EditorModel
    @State private var tab: LibraryTab = .media

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 2) {
                ForEach(LibraryTab.allCases, id: \.self) { t in
                    Button {
                        tab = t
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: t.icon).font(.system(size: 15))
                            Text(t.title).font(.system(size: 10))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .foregroundStyle(tab == t ? Theme.accent : Theme.secondary)
                        .background(RoundedRectangle(cornerRadius: 6).fill(tab == t ? Theme.raised : .clear))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(6)
            Divider().overlay(Theme.border)
            Group {
                switch tab {
                case .media: MediaTab(model: model)
                case .audio: AudioTab(model: model)
                case .text: SubtitlePanel(model: model)
                case .transition: TransitionTab(model: model)
                case .filter: FilterTab(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .background(Theme.panel)
        .overlay(alignment: .trailing) { Rectangle().fill(Theme.border).frame(width: 1) }
    }
}

// MARK: - 素材

private struct MediaTab: View {
    @Bindable var model: EditorModel

    private var visualAssets: [MediaAsset] { model.project.assets.filter { $0.kind != .audio } }

    var body: some View {
        VStack(spacing: 10) {
            Button {
                model.importPanel(addToTimeline: false)
            } label: {
                Label("导入素材", systemImage: "plus").frame(maxWidth: .infinity)
            }
            .buttonStyle(PanelButtonStyle(prominent: true))
            if visualAssets.isEmpty {
                Spacer()
                Text("导入视频或照片，\n也可以直接拖到窗口里").multilineTextAlignment(.center).foregroundStyle(Theme.tertiary)
                Spacer()
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                        ForEach(visualAssets) { asset in
                            AssetCard(asset: asset) {
                                model.store.perform { $0.appendToMain(assetID: asset.id) }
                            }
                        }
                    }
                }
            }
        }
        .padding(10)
    }
}

private struct AssetCard: View {
    let asset: MediaAsset
    let add: () -> Void
    @State private var thumb: CGImage?
    @State private var hovering = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Rectangle().fill(Theme.raised)
                .aspectRatio(16 / 10, contentMode: .fit)
                .overlay {
                    if let thumb {
                        Image(decorative: thumb, scale: 1).resizable().scaledToFill()
                    } else {
                        Image(systemName: asset.kind == .image ? "photo" : "film").foregroundStyle(Theme.tertiary)
                    }
                }
                .clipped()
            if asset.hdr != nil {
                HDRBadge(small: true).padding(4).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
            Text(asset.kind == .image ? "照片" : asset.duration.displayString)
                .font(.system(size: 9).monospacedDigit())
                .padding(.horizontal, 4).padding(.vertical, 1)
                .background(Color.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 3))
                .foregroundStyle(.white)
                .padding(4)
            if hovering {
                Button(action: add) {
                    Image(systemName: "plus").font(.system(size: 11, weight: .bold))
                        .frame(width: 22, height: 22)
                        .background(Theme.accent, in: Circle())
                        .foregroundStyle(.black)
                }
                .buttonStyle(.plain)
                .padding(4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .help("添加到时间线末尾")
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(hovering ? Theme.accent.opacity(0.6) : .clear, lineWidth: 1))
        .onHover { hovering = $0 }
        .onTapGesture(count: 2, perform: add)
        .draggable(AssetDrag.prefix + asset.id.uuidString)
        .help(asset.hdr.map { "\(asset.name)（\($0.displayName)）" } ?? asset.name)
        .task(id: asset.path) {
            thumb = await Thumbnails.shared.thumbnail(url: asset.url, time: Time(seconds: min(1, asset.duration.seconds / 2)), maxHeight: 90, hdr: asset.hdr)
        }
    }
}

enum AssetDrag {
    static let prefix = "framecut-asset:"
    static func assetID(_ s: String) -> UUID? {
        guard s.hasPrefix(prefix) else { return nil }
        return UUID(uuidString: String(s.dropFirst(prefix.count)))
    }
}

// MARK: - 音频

private struct AudioTab: View {
    @Bindable var model: EditorModel

    private var audioAssets: [MediaAsset] { model.project.assets.filter { $0.kind == .audio } }

    var body: some View {
        VStack(spacing: 10) {
            Button {
                model.importPanel(addToTimeline: false, audioOnly: true)
            } label: {
                Label("导入音乐", systemImage: "plus").frame(maxWidth: .infinity)
            }
            .buttonStyle(PanelButtonStyle(prominent: true))
            if audioAssets.isEmpty {
                Spacer()
                Text("导入本地音乐文件（mp3 / m4a / wav）\n作为背景音乐").multilineTextAlignment(.center).foregroundStyle(Theme.tertiary)
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(audioAssets) { asset in
                            HStack(spacing: 10) {
                                Image(systemName: "music.note")
                                    .frame(width: 32, height: 32)
                                    .background(Theme.musicClip, in: RoundedRectangle(cornerRadius: 6))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(asset.name).font(.system(size: 12)).lineLimit(1)
                                    Text(asset.duration.displayString).font(.system(size: 10).monospacedDigit()).foregroundStyle(Theme.tertiary)
                                }
                                Spacer()
                                Button {
                                    let at = model.playhead
                                    model.store.perform { _ = $0.addMusic(assetID: asset.id, at: at) }
                                } label: {
                                    Image(systemName: "plus.circle.fill").font(.system(size: 18)).foregroundStyle(Theme.accent)
                                }
                                .buttonStyle(.plain)
                                .help("添加到播放头位置")
                            }
                            .padding(8)
                            .background(Theme.raised, in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }
        }
        .padding(10)
        .foregroundStyle(Theme.text)
    }
}

// MARK: - 转场

private struct TransitionTab: View {
    @Bindable var model: EditorModel
    @State private var duration = 0.5

    /// 当前要设置转场的交界：选中转场，或选中的片段（与前一片段之间）。
    private var targetClipID: UUID? {
        switch model.selection {
        case .transition(let id): return id
        case .video(let id):
            guard let i = model.project.mainTrack.firstIndex(where: { $0.id == id }), i > 0 else { return nil }
            return id
        default: return nil
        }
    }

    private var currentKind: TransitionKind? {
        targetClipID.flatMap { model.project.transitions[$0]?.kind }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(targetClipID == nil ? "在时间线上点击两个片段之间的 ◇ 选择位置" : "点击应用到所选位置")
                .font(.system(size: 11))
                .foregroundStyle(targetClipID == nil ? Theme.tertiary : Theme.secondary)
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 86), spacing: 8)], spacing: 8) {
                    tile(nil)
                    ForEach(TransitionKind.allCases, id: \.self) { tile($0) }
                }
            }
            LabeledSlider(title: "时长", value: $duration, range: 0.2...2, format: { String(format: "%.1f 秒", $0) })
            Button {
                model.store.perform { $0.applyTransitionToAll(FCCore.Transition(kind: currentKind ?? .dissolve, duration: Time(seconds: duration))) }
            } label: {
                Text("应用到全部（\(currentKind?.displayName ?? TransitionKind.dissolve.displayName)）").frame(maxWidth: .infinity)
            }
            .buttonStyle(PanelButtonStyle())
            .disabled(model.project.mainTrack.count < 2)
        }
        .padding(10)
    }

    private func tile(_ kind: TransitionKind?) -> some View {
        let selected = targetClipID != nil && currentKind == kind
        return Button {
            guard let id = targetClipID else { return }
            model.store.perform { $0.setTransition(kind.map { FCCore.Transition(kind: $0, duration: Time(seconds: duration)) }, before: id) }
            model.selection = .transition(id)
        } label: {
            VStack(spacing: 6) {
                Image(systemName: kind.map(Self.icon) ?? "nosign")
                    .font(.system(size: 20))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Theme.raised, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(selected ? Theme.accent : .clear, lineWidth: 2))
                Text(kind?.displayName ?? "无").font(.system(size: 11))
            }
            .foregroundStyle(targetClipID == nil ? Theme.tertiary : Theme.text)
        }
        .buttonStyle(.plain)
    }

    static func icon(_ kind: TransitionKind) -> String {
        switch kind {
        case .dissolve: "circle.lefthalf.filled"
        case .fadeBlack: "moon.fill"
        case .fadeWhite: "sun.max.fill"
        case .pushLeft: "arrow.left.square"
        case .pushRight: "arrow.right.square"
        case .pushUp: "arrow.up.square"
        case .pushDown: "arrow.down.square"
        case .slideLeft: "rectangle.righthalf.inset.filled.arrow.right"
        case .wipeLeft: "rectangle.split.2x1"
        case .zoom: "plus.magnifyingglass"
        case .blur: "drop.halffull"
        }
    }
}

// MARK: - 滤镜

private struct FilterTab: View {
    @Bindable var model: EditorModel
    @State private var source: CGImage?
    @State private var previews: [FilterPreset: CGImage] = [:]

    private var clip: VideoClip? { model.selectedClip }
    private var sampleClip: VideoClip? { clip ?? model.project.mainTrack.first }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(clip == nil ? "先在时间线上选中一个片段" : "点击应用到所选片段")
                .font(.system(size: 11))
                .foregroundStyle(clip == nil ? Theme.tertiary : Theme.secondary)
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 86), spacing: 8)], spacing: 10) {
                    ForEach(FilterPreset.allCases, id: \.self) { preset in
                        Button {
                            guard let id = clip?.id else { return }
                            model.store.perform { $0.updateMain(id: id) { $0.filter.preset = preset; if $0.filter.intensity == 0 { $0.filter.intensity = 1 } } }
                        } label: {
                            VStack(spacing: 5) {
                                Rectangle().fill(Theme.raised)
                                    .aspectRatio(1.4, contentMode: .fit)
                                    .overlay {
                                        if let img = previews[preset] { Image(decorative: img, scale: 1).resizable().scaledToFill() }
                                    }
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(clip?.filter.preset == preset ? Theme.accent : .clear, lineWidth: 2))
                                Text(preset.displayName).font(.system(size: 11))
                            }
                            .foregroundStyle(clip == nil ? Theme.tertiary : Theme.text)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if let clip {
                LabeledSlider(title: "强度", value: model.clipBinding(clip.id, \.filter.intensity, default: 1), range: 0...1,
                              onEditing: model.coalesce)
                Button {
                    model.store.perform { $0.applyFilterToAll(clip.filter) }
                } label: {
                    Text("应用到全部片段").frame(maxWidth: .infinity)
                }
                .buttonStyle(PanelButtonStyle())
            }
        }
        .padding(10)
        .task(id: sampleClip?.id) { await loadPreviews() }
    }

    private func loadPreviews() async {
        guard let clip = sampleClip, let asset = model.project.asset(id: clip.assetID) else {
            previews = [:]
            return
        }
        guard let base = await Thumbnails.shared.thumbnail(url: asset.url, time: clip.sourceIn + clip.sourceDuration / 2, maxHeight: 80, hdr: asset.hdr) else { return }
        var result: [FilterPreset: CGImage] = [:]
        for preset in FilterPreset.allCases {
            result[preset] = preset == .none ? base : FilterPreview.render(base, preset: preset)
        }
        previews = result
    }
}
