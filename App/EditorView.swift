import FCCore
import SwiftUI
import UniformTypeIdentifiers

/// 编辑器：顶栏 / 素材库 · 预览 · 检查器 / 工具条 / 时间线。
struct EditorView: View {
    @Bindable var model: EditorModel
    @Environment(AppModel.self) private var app
    @State private var dropTargeted = false
    @AppStorage("layout.libraryWidth") private var libraryWidth = 320.0
    @AppStorage("layout.inspectorWidth") private var inspectorWidth = 300.0
    @AppStorage("layout.timelineHeight") private var timelineHeight = 250.0
    @AppStorage("layout.showLibrary") private var showLibrary = true
    @AppStorage("layout.showInspector") private var showInspector = true

    var body: some View {
        VStack(spacing: 0) {
            TopBar(model: model, showLibrary: $showLibrary, showInspector: $showInspector)
            HStack(spacing: 0) {
                if showLibrary {
                    LibraryPanel(model: model)
                        .frame(width: libraryWidth)
                    ResizeHandle(axis: .horizontal, value: $libraryWidth, range: 240...520)
                }
                PlayerPanel(model: model)
                    .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
                if showInspector {
                    ResizeHandle(axis: .horizontal, value: $inspectorWidth, range: 260...480, inverted: true)
                    InspectorPanel(model: model)
                        .frame(width: inspectorWidth)
                }
            }
            .frame(minHeight: 240, maxHeight: .infinity)
            ResizeHandle(axis: .vertical, value: $timelineHeight, range: 150...560, inverted: true)
            TimelineToolbar(model: model)
            TimelineView(model: model)
                .frame(height: timelineHeight)
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
        .overlay(alignment: .top) {
            if let notice = model.notice {
                HStack(spacing: 10) {
                    Image(systemName: "sun.max.fill").foregroundStyle(Theme.playhead)
                    Text(notice).font(.system(size: 12))
                    Button { model.notice = nil } label: { Image(systemName: "xmark").font(.system(size: 10)) }
                        .buttonStyle(.plain)
                }
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(Theme.raised, in: Capsule())
                .overlay(Capsule().stroke(Theme.border))
                .foregroundStyle(Theme.text)
                .padding(.top, 52)
                // 以提示内容为 id：新提示会重新计时，旧计时不会提前关掉新提示
                .task(id: notice) {
                    try? await Task.sleep(nanoseconds: 8_000_000_000)
                    if !Task.isCancelled, model.notice == notice { model.notice = nil }
                }
            }
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
    @Binding var showLibrary: Bool
    @Binding var showInspector: Bool
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
            if model.project.colorMode == .hdr { HDRBadge() }
            if let saved = model.lastSaved {
                Text("已自动保存 \(saved.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.tertiary)
            }
            Spacer()
            panelToggle("sidebar.left", on: $showLibrary, help: "显示 / 隐藏素材库")
            panelToggle("sidebar.right", on: $showInspector, help: "显示 / 隐藏属性面板")
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

    private func panelToggle(_ icon: String, on: Binding<Bool>, help: String) -> some View {
        Button { withAnimation(.easeOut(duration: 0.15)) { on.wrappedValue.toggle() } } label: {
            Image(systemName: icon).font(.system(size: 14))
        }
        .buttonStyle(.plain)
        .foregroundStyle(on.wrappedValue ? Theme.text : Theme.tertiary)
        .help(help)
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
                .help("缩放时间线：触控板捏合，或按住 ⌘ / ⌥ 滚动滚轮")
            Slider(value: Binding(get: { log(model.pointsPerSecond) },
                                  set: { model.zoom(by: exp($0) / model.pointsPerSecond) }),
                   in: log(TimelineZoom.minPointsPerSecond)...log(TimelineZoom.maxPointsPerSecond))
                .frame(width: 140)
                .controlSize(.mini)
                .tint(Theme.accent)
            Image(systemName: "plus.magnifyingglass").foregroundStyle(Theme.tertiary)
            toolButton("arrow.left.and.right.square", "适应窗口 ⌘0", enabled: !model.project.mainTrack.isEmpty) { model.zoomToFit() }
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

/// HDR 标记。
struct HDRBadge: View {
    var small = false

    var body: some View {
        Text("HDR")
            .font(.system(size: small ? 8 : 10, weight: .heavy))
            .padding(.horizontal, small ? 3 : 5)
            .padding(.vertical, small ? 0 : 1)
            .foregroundStyle(.black)
            .background(LinearGradient(colors: [Color(red: 1, green: 0.86, blue: 0.3), Color(red: 1, green: 0.6, blue: 0.2)],
                                       startPoint: .leading, endPoint: .trailing),
                        in: RoundedRectangle(cornerRadius: 3))
    }
}
