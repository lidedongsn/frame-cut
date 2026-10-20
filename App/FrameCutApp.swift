import FCCore
import FCEngine
import FCMedia
import FCTranscribe
import SwiftUI

@main
struct FrameCutApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @State private var app = AppModel()

    init() {
        UserLUTLibrary.shared.load()
    }

    var body: some Scene {
        Window("FrameCut", id: "main") {
            RootView()
                .environment(app)
                .preferredColorScheme(.dark)
                .onAppear {
                    delegate.app = app
                    DebugSnapshot.scheduleIfRequested(app: app)
                    // 开发调试：-open <工程路径> 启动后直接打开
                    let args = CommandLine.arguments
                    if let i = args.firstIndex(of: "-open"), i + 1 < args.count {
                        app.open(url: URL(fileURLWithPath: args[i + 1]))
                    }
                }
        }
        .defaultSize(width: 1440, height: 900)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("新建工程…") { app.newProject() }.keyboardShortcut("n")
                Button("打开工程…") { app.openPanel() }.keyboardShortcut("o")
            }
            CommandGroup(replacing: .saveItem) {
                Button("保存") { app.editor?.save() }.keyboardShortcut("s").disabled(app.editor == nil)
                Button("关闭工程") { app.closeProject() }.keyboardShortcut("w", modifiers: [.command, .shift]).disabled(app.editor == nil)
            }
            CommandGroup(replacing: .undoRedo) {
                Button("撤销") { app.undo() }.keyboardShortcut("z")
                Button("重做") { app.redo() }.keyboardShortcut("z", modifiers: [.command, .shift])
            }
            CommandMenu("剪辑") {
                Button("分割") { app.editor?.splitAtPlayhead() }.keyboardShortcut("b").disabled(app.editor == nil)
                Button("删除所选") { app.editor?.deleteSelection() }.disabled(app.editor?.selection == nil)
                Divider()
                Button("复制调色") { app.editor?.copyGrade() }
                    .keyboardShortcut("c", modifiers: [.command, .option]).disabled(app.editor?.selectedClip == nil)
                Button("粘贴调色") { app.editor?.pasteGrade() }
                    .keyboardShortcut("v", modifiers: [.command, .option])
                    .disabled(app.editor?.selectedClip == nil || app.editor?.copiedFilter == nil)
                Divider()
                Button("放大时间线") { app.editor?.zoom(by: 1.4) }.keyboardShortcut("=").disabled(app.editor == nil)
                Button("缩小时间线") { app.editor?.zoom(by: 1 / 1.4) }.keyboardShortcut("-").disabled(app.editor == nil)
                Button("时间线适应窗口") { app.editor?.zoomToFit() }.keyboardShortcut("0").disabled(app.editor == nil)
                Divider()
                Button("导出…") { app.editor?.showExport = true }.keyboardShortcut("e").disabled(app.editor == nil)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var app: AppModel?

    private var memoryPressure: DispatchSourceMemoryPressure?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// 系统内存紧张时释放缓存；严重时连语音模型一起释放。
    func applicationDidFinishLaunching(_ notification: Notification) {
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        source.setEventHandler { [weak source] in
            let critical = source?.data.contains(.critical) ?? false
            MainActor.assumeIsolated { AppModel.purgeCaches() }
            if critical { Task { await WhisperKitTranscriber.shared.unload() } }
        }
        source.resume()
        memoryPressure = source
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { app?.editor?.save() }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app
        Group {
            if let editor = app.editor {
                EditorView(model: editor)
                    .id(editor.packageURL)
            } else {
                LauncherView()
            }
        }
        .frame(minWidth: 1100, minHeight: 700)
        .background(Theme.window)
        .ignoresSafeArea(.container, edges: .top)
        .alert("提示", isPresented: Binding(get: { app.alert != nil }, set: { if !$0 { app.alert = nil } })) {
            Button("好") { app.alert = nil }
        } message: {
            Text(app.alert ?? "")
        }
    }
}

/// 应用共用的缩略图提供者，HDR 帧按成片同样的方式色调映射。
enum Thumbnails {
    static let shared = ThumbnailProvider(hdrToneMapper: { image, format in HDRThumbnail.toneMap(image, format: format) })
}

/// 应用共用的调色预设库。
@MainActor
enum GradePresets {
    static let store = GradePresetStore()
}
