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

    /// 连续操作期间换算的起点，以及上一次换算的结果。字幕、文字各记各的。
    private struct FollowState<Items: Equatable> {
        var base: Project?
        var output: Items?
    }

    private var subtitleFollow = FollowState<[Subtitle]>()
    private var textFollow = FollowState<[TextClip]>()
    private var duckFollow = FollowState<[DuckRange]>()

    /// 主轨时间布局变了时，这次没有改动的字幕（开启跟随时）、文字和人声区间跟随主轨。
    /// 连续操作（拖动修剪）期间从同一个起点换算，拖回原处时也回到原处；
    /// 期间被别处改过（如识别完成）就以改过的状态为新起点，不覆盖它。
    private func followMain(_ next: inout Project) {
        if next.subtitlesFollowMain, next.subtitles == project.subtitles {
            let base = followBase(&subtitleFollow, current: project.subtitles)
            if base.subtitlesFollowMain, let changed = layoutChanged(from: base, to: next) {
                next.subtitles = changed ? next.subtitlesFollowingMain(from: base) : base.subtitles
                subtitleFollow.output = next.subtitles
            }
        }
        if next.texts == project.texts {
            let base = followBase(&textFollow, current: project.texts)
            if let changed = layoutChanged(from: base, to: next) {
                next.texts = changed ? next.textsFollowingMain(from: base) : base.texts
                textFollow.output = next.texts
            }
        }
        if next.duckRanges == project.duckRanges {
            let base = followBase(&duckFollow, current: project.duckRanges)
            if let changed = layoutChanged(from: base, to: next) {
                next.duckRanges = changed ? next.duckRangesFollowingMain(from: base) : base.duckRanges
                duckFollow.output = next.duckRanges
            }
        }
    }

    /// 当前值不是上次换算的结果（被别处改过）时，以当前工程为新起点。
    private func followBase<Items>(_ state: inout FollowState<Items>, current: Items) -> Project {
        guard coalescingDepth > 0 else { return project }
        if state.base == nil || state.output != current { state.base = project }
        return state.base ?? project
    }

    /// 时间布局是否变了；nil 表示不需要换算（非连续操作且布局没变）。
    private func layoutChanged(from base: Project, to next: Project) -> Bool? {
        let changed = TimelineLayout(project: base) != TimelineLayout(project: next)
        return changed || coalescingDepth > 0 ? changed : nil
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
        subtitleFollow = FollowState()
        textFollow = FollowState()
        duckFollow = FollowState()
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
