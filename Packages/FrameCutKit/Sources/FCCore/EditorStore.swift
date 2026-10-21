import Foundation
import Observation

/// 持有当前工程，所有修改经由 perform，支持撤销重做与连续操作合并。
@Observable
@MainActor
public final class EditorStore {
    public static let undoLimit = 100

    public private(set) var project: Project
    @ObservationIgnored public var onChange: ((Project) -> Void)?

    @ObservationIgnored private var undoStack: [Project] = []
    @ObservationIgnored private var redoStack: [Project] = []
    @ObservationIgnored private var coalescingDepth = 0
    @ObservationIgnored private var coalescingSnapshot: Project?
    public private(set) var canUndo = false
    public private(set) var canRedo = false

    public init(project: Project) {
        self.project = project
    }

    public func perform(_ body: (inout Project) -> Void) {
        var next = project
        body(&next)
        guard next != project else { return }
        followMain(&next)
        if coalescingDepth == 0 {
            pushUndo(project)
        }
        project = next
        onChange?(project)
    }

    /// 连续操作期间字幕换算的起点，以及上一次换算的结果。
    private var followBase: Project?
    private var followOutput: [Subtitle]?

    /// 主轨时间布局变了且这次没有改字幕时，字幕跟随主轨。
    /// 连续操作（拖动修剪）期间从同一个起点换算，拖回去时字幕也能回来；
    /// 期间字幕被别处改过（如识别完成）就以改过的状态为新起点，不覆盖它。
    private func followMain(_ next: inout Project) {
        guard next.subtitlesFollowMain, next.subtitles == project.subtitles else { return }
        let base: Project
        if coalescingDepth > 0 {
            if followBase == nil || project.subtitles != followOutput { followBase = project }
            base = followBase ?? project
        } else {
            base = project
        }
        guard base.subtitlesFollowMain, TimelineLayout(project: base) != TimelineLayout(project: next) else { return }
        next.subtitles = next.subtitlesFollowingMain(from: base)
        followOutput = next.subtitles
    }

    /// 开始一段连续操作（如拖动滑块），期间的修改只记一次撤销。
    public func beginCoalescing() {
        if coalescingDepth == 0 { coalescingSnapshot = project }
        coalescingDepth += 1
    }

    public func endCoalescing() {
        guard coalescingDepth > 0 else { return }
        coalescingDepth -= 1
        guard coalescingDepth == 0, let snapshot = coalescingSnapshot else { return }
        coalescingSnapshot = nil
        followBase = nil
        followOutput = nil
        if snapshot != project { pushUndo(snapshot) }
    }

    public func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(project)
        project = previous
        updateFlags()
        onChange?(project)
    }

    public func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(project)
        project = next
        updateFlags()
        onChange?(project)
    }

    private func pushUndo(_ snapshot: Project) {
        undoStack.append(snapshot)
        if undoStack.count > EditorStore.undoLimit { undoStack.removeFirst(undoStack.count - EditorStore.undoLimit) }
        redoStack.removeAll()
        updateFlags()
    }

    private func updateFlags() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }
}
