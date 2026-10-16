import FCCore
import SwiftUI
import UniformTypeIdentifiers

/// 编辑器：顶栏 / 素材库 · 预览 · 检查器 / 工具条 / 时间线。
struct EditorView: View {
    @Bindable var model: EditorModel
    @Environment(AppModel.self) private var app
    @State private var dropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            TopBar(model: model)
            HStack(spacing: 0) {
                LibraryPanel(model: model)
                    .frame(width: 320)
                PlayerPanel(model: model)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                InspectorPanel(model: model)
                    .frame(width: 300)
            }
            .frame(maxHeight: .infinity)
            TimelineToolbar(model: model)
            TimelineView(model: model)
                .frame(height: 250)
        }
        .background(Theme.window)
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 12).stroke(Theme.accent, lineWidth: 3).padding(4).allowsHitTesting(false)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            loadFileURLs(providers) { urls in Task { await model.importFiles(urls, addToTimeline: true) } }
            return true
        }
        .sheet(isPresented: $model.showExport) {
            ExportSheet(model: model)
        }
        .sheet(isPresented: Binding(get: { !model.missingAssets.isEmpty }, set: { if !$0 { model.missingAssets = [] } })) {
            MissingAssetsSheet(model: model)
        }
        .alert("提示", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("好") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

func loadFileURLs(_ providers: [NSItemProvider], completion: @escaping @MainActor ([URL]) -> Void) {
    let group = DispatchGroup()
    let lock = NSLock()
    var urls: [URL] = []
    for provider in providers {
        group.enter()
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            if let url {
                lock.lock()
                urls.append(url)
                lock.unlock()
            }
            group.leave()
        }
    }
    group.notify(queue: .main) {
        MainActor.assumeIsolated { completion(urls.sorted { $0.lastPathComponent < $1.lastPathComponent }) }
    }
}

// MARK: - 顶栏

private struct TopBar: View {
    @Bindable var model: EditorModel
    @Environment(AppModel.self) private var app

    var body: some View {
        HStack(spacing: 12) {
            Button {
                app.closeProject()
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.secondary)
            .help("返回首页")

            Text(model.project.name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.text)
            if let saved = model.lastSaved {
                Text("已自动保存 \(saved.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.tertiary)
            }
            Spacer()
            if model.importing {
                ProgressView().controlSize(.small)
                Text("正在导入…").font(.system(size: 11)).foregroundStyle(Theme.secondary)
            }
            Button {
                model.showExport = true
            } label: {
                Label("导出", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(PanelButtonStyle(prominent: true))
            .disabled(model.project.mainTrack.isEmpty)
        }
        .padding(.leading, 84)
        .padding(.trailing, 14)
        .frame(height: 44)
        .background(Theme.panel)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }
    }
}

// MARK: - 时间线工具条

private struct TimelineToolbar: View {
    @Bindable var model: EditorModel

    var body: some View {
        HStack(spacing: 4) {
            toolButton("arrow.uturn.backward", "撤销 ⌘Z", enabled: model.store.canUndo) { model.store.undo() }
            toolButton("arrow.uturn.forward", "重做 ⇧⌘Z", enabled: model.store.canRedo) { model.store.redo() }
            Divider().frame(height: 16).padding(.horizontal, 6)
            toolButton("scissors", "分割 ⌘B", enabled: !model.project.mainTrack.isEmpty) { model.splitAtPlayhead() }
            toolButton("trash", "删除 ⌫", enabled: model.selection != nil) { model.deleteSelection() }
            Spacer()
            Text("\(model.playhead.displayString) / \(model.duration.displayString)")
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(Theme.secondary)
            Spacer()
            Image(systemName: "minus.magnifyingglass").foregroundStyle(Theme.tertiary)
            Slider(value: Binding(get: { log(model.pointsPerSecond) }, set: { model.pointsPerSecond = exp($0) }),
                   in: log(8)...log(600))
                .frame(width: 140)
                .controlSize(.mini)
                .tint(Theme.accent)
            Image(systemName: "plus.magnifyingglass").foregroundStyle(Theme.tertiary)
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(Theme.panel)
        .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 1) }
    }

    private func toolButton(_ icon: String, _ help: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .frame(width: 28, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? Theme.text : Theme.tertiary)
        .disabled(!enabled)
        .help(help)
    }
}

// MARK: - 丢失素材

private struct MissingAssetsSheet: View {
    @Bindable var model: EditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("有素材找不到了").font(.headline)
            Text("这些文件可能被移动或删除。重新定位后即可继续编辑。")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            ForEach(model.missingAssets) { asset in
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    VStack(alignment: .leading) {
                        Text(asset.name)
                        Text(asset.path).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                    Spacer()
                    Button("重新定位…") { model.relink(asset) }
                }
            }
            HStack {
                Spacer()
                Button("稍后处理") { model.missingAssets = [] }
            }
        }
        .padding(20)
        .frame(width: 520)
    }
}
