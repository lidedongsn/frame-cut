import AppKit
import FCCore
import FCEngine
import FCMedia
import Observation
import UniformTypeIdentifiers

/// 应用级状态：当前打开的工程，或启动页。
@Observable
@MainActor
final class AppModel {
    var editor: EditorModel?
    var recent: [URL] = RecentProjects().list()
    var alert: String?

    static let projectType = UTType(exportedAs: "com.lidedongsn.framecut.project", conformingTo: .package)

    func newProject() {
        let panel = NSSavePanel()
        panel.title = "新建工程"
        panel.nameFieldStringValue = "未命名工程"
        panel.allowedContentTypes = [Self.projectType]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let packageURL = url.pathExtension == ProjectFile.fileExtension ? url : url.appendingPathExtension(ProjectFile.fileExtension)
        do {
            try? FileManager.default.removeItem(at: packageURL)
            try ProjectFile.write(Project(name: packageURL.deletingPathExtension().lastPathComponent), to: packageURL)
            open(url: packageURL)
        } catch {
            alert = "无法创建工程：\(error.localizedDescription)"
        }
    }

    func openPanel() {
        let panel = NSOpenPanel()
        panel.title = "打开工程"
        panel.allowedContentTypes = [Self.projectType]
        panel.treatsFilePackagesAsDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        open(url: url)
    }

    func open(url: URL) {
        do {
            let project = try ProjectFile.read(from: url)
            if editor != nil {
                editor?.close()
                Self.purgeCaches()
            }
            editor = EditorModel(project: project, packageURL: url)
            RecentProjects().add(url)
            recent = RecentProjects().list()
        } catch {
            alert = "无法打开工程：\(error.localizedDescription)"
            Log.project.error("无法打开工程：\(error.localizedDescription, privacy: .public)")
            RecentProjects().remove(url)
            recent = RecentProjects().list()
        }
    }

    func closeProject() {
        editor?.close()
        editor = nil
        recent = RecentProjects().list()
        Self.purgeCaches()
    }

    /// 释放缩略图、波形、照片、滤镜与字幕的内存缓存（关闭工程或系统内存紧张时）。
    static func purgeCaches() {
        Log.cache.info("释放内存缓存")
        RenderCaches.purge()
        Task {
            await Thumbnails.shared.purge()
            await WaveformProvider.shared.purge()
        }
    }

    // 文本框聚焦时，撤销交给文本框自己。
    private var textIsEditing: Bool { NSApp.keyWindow?.firstResponder is NSText }

    func undo() {
        if textIsEditing { NSApp.sendAction(Selector(("undo:")), to: nil, from: nil) } else { editor?.store.undo() }
    }

    func redo() {
        if textIsEditing { NSApp.sendAction(Selector(("redo:")), to: nil, from: nil) } else { editor?.store.redo() }
    }
}
