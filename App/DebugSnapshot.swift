import AppKit

/// 开发调试：`-snapshot <png 路径> [-snapshotDelay 秒] [-autoplay] [-zoomFit]` 启动后把主窗口内容存为 PNG。
enum DebugSnapshot {
    @MainActor
    static func scheduleIfRequested(app: AppModel) {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "-snapshot"), i + 1 < args.count else { return }
        let path = args[i + 1]
        var delay = 3.0
        if let j = args.firstIndex(of: "-snapshotDelay"), j + 1 < args.count, let d = Double(args[j + 1]) { delay = d }
        if args.contains("-zoomFit") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { app.editor?.zoomToFit() }
        }
        if args.contains("-autoplay") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { app.editor?.togglePlay() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            if let editor = app.editor {
                NSLog("FCDEBUG playhead=%.2f duration=%.2f playing=%d rate=%.1f pps=%.2f", editor.playhead.seconds, editor.duration.seconds,
                      editor.isPlaying ? 1 : 0, editor.player.rate, editor.pointsPerSecond)
            }
            guard let view = NSApp.windows.first(where: { $0.isVisible })?.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        }
    }
}
