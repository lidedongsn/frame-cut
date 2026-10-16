import AppKit
import AVFoundation
import FCCore
import FCEngine
import FCMedia
import FCTranscribe
import Observation

enum Selection: Equatable {
    case video(UUID)
    case music(UUID)
    case subtitle(UUID)
    /// 转场，以其后的片段 id 标识。
    case transition(UUID)
}

enum ExportState: Equatable {
    case idle
    case running(Double)
    case done(URL)
    case failed(String)
}

enum TranscribeState: Equatable {
    case idle
    case running(String, Double?)
    case failed(String)
}

/// 一个打开的工程：编辑状态、播放器、自动保存、导出与识别。
@Observable
@MainActor
final class EditorModel {
    static let previewShortSide = 720
    static let autosaveDelay: UInt64 = 2_000_000_000

    let store: EditorStore
    let packageURL: URL
    let player = AVPlayer()

    var playhead: Time = .zero
    var isPlaying = false
    var selection: Selection?
    /// 时间线缩放：每秒多少点。
    var pointsPerSecond: Double = 60
    private(set) var layout: TimelineLayout
    private(set) var duration: Time = .zero
    var missingAssets: [MediaAsset] = []
    var exportState: ExportState = .idle
    var showExport = false
    var transcribeState: TranscribeState = .idle
    var errorMessage: String?
    var lastSaved: Date?
    var importing = false

    var project: Project { store.project }

    @ObservationIgnored private var built: BuiltComposition?
    @ObservationIgnored private var rebuildTask: Task<Void, Never>?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var exportTask: Task<Void, Never>?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var keyMonitor: Any?
    @ObservationIgnored private var seekTarget: Time?
    @ObservationIgnored private var isSeeking = false

    init(project: Project, packageURL: URL) {
        store = EditorStore(project: project)
        self.packageURL = packageURL
        layout = TimelineLayout(project: project)
        player.actionAtItemEnd = .pause
        store.onChange = { [weak self] _ in self?.projectChanged() }
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 30), queue: .main) { [weak self] time in
            MainActor.assumeIsolated { self?.playerTick(time) }
        }
        installKeyMonitor()
        checkMissingAssets()
        scheduleRebuild(immediate: true)
    }

    func close() {
        save()
        exportTask?.cancel()
        player.pause()
        player.replaceCurrentItem(with: nil)
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        timeObserver = nil
        keyMonitor = nil
    }

    // MARK: 变更

    private func projectChanged() {
        layout = TimelineLayout(project: store.project)
        validateSelection()
        scheduleRebuild()
        scheduleAutosave()
    }

    private func validateSelection() {
        switch selection {
        case .video(let id), .transition(let id):
            if project.mainClip(id: id) == nil { selection = nil }
        case .music(let id):
            if project.music(id: id) == nil { selection = nil }
        case .subtitle(let id):
            if project.subtitle(id: id) == nil { selection = nil }
        case nil:
            break
        }
    }

    // MARK: 播放

    var previewSize: CGSize { RenderSize.size(aspect: project.aspect, shortSide: Self.previewShortSide) }

    func scheduleRebuild(immediate: Bool = false) {
        rebuildTask?.cancel()
        rebuildTask = Task { [weak self] in
            if !immediate { try? await Task.sleep(nanoseconds: 120_000_000) }
            guard !Task.isCancelled else { return }
            await self?.rebuild()
        }
    }

    private func rebuild() async {
        let project = store.project
        let size = previewSize
        guard !layout.placements.isEmpty else {
            built = nil
            duration = .zero
            player.replaceCurrentItem(with: nil)
            isPlaying = false
            playhead = .zero
            return
        }
        if let built, built.structureKey == CompositionBuilder.structureKey(project), let item = player.currentItem {
            item.videoComposition = built.makeVideoComposition(project: project, renderSize: size)
            item.audioMix = built.makeAudioMix(project: project)
            if !isPlaying { seek(to: playhead) }
            return
        }
        do {
            let next = try await CompositionBuilder.build(project: project, renderSize: size)
            guard !Task.isCancelled, project == store.project else { return }
            let item = AVPlayerItem(asset: next.composition)
            item.videoComposition = next.makeVideoComposition(project: project, renderSize: size)
            item.audioMix = next.makeAudioMix(project: project)
            item.audioTimePitchAlgorithm = .spectral
            built = next
            duration = next.duration
            let wasPlaying = isPlaying
            player.replaceCurrentItem(with: item)
            seek(to: Time.min(playhead, duration))
            if wasPlaying { player.play() }
        } catch CompositionError.missingAsset {
            checkMissingAssets() // 由“重新定位”窗口提示，不再弹错误框
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func playerTick(_ time: CMTime) {
        guard isPlaying else { return }
        playhead = Time(time)
        if player.rate == 0 {
            isPlaying = false
        }
    }

    func togglePlay() {
        guard duration > .zero else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            if playhead >= duration - Time(seconds: 0.05) { seek(to: .zero) }
            player.play()
            isPlaying = true
        }
    }

    /// 连续拖动时只保留最新目标，避免排队卡顿。
    func seek(to t: Time) {
        let target = t.clamped(.zero, duration)
        playhead = target
        seekTarget = target
        if !isSeeking { performSeek() }
    }

    private func performSeek() {
        guard let target = seekTarget, player.currentItem != nil else {
            isSeeking = false
            return
        }
        seekTarget = nil
        isSeeking = true
        player.seek(to: target.cmTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in
                self?.isSeeking = false
                self?.performSeek()
            }
        }
    }

    func step(frames: Int) {
        if isPlaying { togglePlay() }
        seek(to: playhead + Time(seconds: Double(frames) / Double(project.frameRate)))
    }

    func zoom(by factor: Double) {
        pointsPerSecond = min(600, max(8, pointsPerSecond * factor))
    }

    // MARK: 编辑

    func splitAtPlayhead() {
        let t = playhead
        if case .music(let id) = selection, let clip = project.music(id: id), clip.start < t, t < clip.end {
            store.perform { _ = $0.splitMusic(id: id, at: t) }
            return
        }
        var newID: UUID?
        store.perform { newID = $0.splitMain(at: t) }
        if let newID { selection = .video(newID) }
    }

    func deleteSelection() {
        guard let selection else { return }
        store.perform { p in
            switch selection {
            case .video(let id): p.removeMain(id: id)
            case .music(let id): p.removeMusic(id: id)
            case .subtitle(let id): p.removeSubtitle(id: id)
            case .transition(let id): p.setTransition(nil, before: id)
            }
        }
        self.selection = nil
    }

    var selectedClip: VideoClip? {
        if case .video(let id) = selection { return project.mainClip(id: id) }
        return nil
    }

    // MARK: 导入

    func importFiles(_ urls: [URL], addToTimeline: Bool) async {
        importing = true
        defer { importing = false }
        var assets: [MediaAsset] = []
        var failed: [String] = []
        for url in urls {
            if let existing = project.assets.first(where: { $0.path == url.path }) {
                assets.append(existing)
                continue
            }
            do {
                assets.append(try await MediaProbe.probe(url: url))
            } catch {
                failed.append(url.lastPathComponent)
            }
        }
        let at = playhead
        store.perform { p in
            for asset in assets where !p.assets.contains(where: { $0.id == asset.id }) {
                p.assets.append(asset)
            }
            guard addToTimeline else { return }
            for asset in assets {
                switch asset.kind {
                case .video, .image: p.appendToMain(assetID: asset.id)
                case .audio: p.addMusic(assetID: asset.id, at: at)
                }
            }
        }
        if !failed.isEmpty { errorMessage = "以下文件无法导入：\(failed.joined(separator: "、"))" }
    }

    func importPanel(addToTimeline: Bool, audioOnly: Bool = false) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = audioOnly ? [.audio] : MediaProbe.supportedTypes
        guard panel.runModal() == .OK else { return }
        let urls = panel.urls
        Task { await importFiles(urls, addToTimeline: addToTimeline) }
    }

    func checkMissingAssets() {
        missingAssets = project.missingAssets { FileManager.default.fileExists(atPath: $0) }
    }

    func relink(_ asset: MediaAsset) {
        let panel = NSOpenPanel()
        panel.title = "重新定位：\(asset.name)"
        panel.allowedContentTypes = MediaProbe.supportedTypes
        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.perform { $0.relinkAsset(id: asset.id, to: url.path, bookmark: try? url.bookmarkData(options: .minimalBookmark)) }
        checkMissingAssets()
        built = nil
        scheduleRebuild(immediate: true)
    }

    // MARK: 保存

    func scheduleAutosave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.autosaveDelay)
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }

    func save() {
        do {
            try ProjectFile.write(store.project, to: packageURL)
            lastSaved = Date()
        } catch {
            errorMessage = "保存失败：\(error.localizedDescription)"
        }
    }

    // MARK: 导出

    func export(settings: ExportSettings, to url: URL) {
        exportState = .running(0)
        let project = store.project
        exportTask = Task { [weak self] in
            do {
                try await Exporter().export(project: project, settings: settings, to: url) { p in
                    Task { @MainActor in
                        if case .running = self?.exportState { self?.exportState = .running(p) }
                    }
                }
                self?.exportState = .done(url)
            } catch is CancellationError {
                self?.exportState = .idle
            } catch {
                self?.exportState = .failed(error.localizedDescription)
            }
        }
    }

    func cancelExport() {
        exportTask?.cancel()
        exportTask = nil
        exportState = .idle
    }

    // MARK: 字幕识别

    func transcribe() {
        if case .running = transcribeState { return }
        transcribeState = .running("正在提取音频…", nil)
        let project = store.project
        Task { [weak self] in
            do {
                let samples = try await AudioExtractor.mainTrackSamples(project: project)
                guard !samples.isEmpty else {
                    self?.transcribeState = .failed("主轨视频没有声音，无法识别")
                    return
                }
                let segments = try await WhisperKitTranscriber.shared.transcribe(samples: samples) { progress in
                    Task { @MainActor in
                        switch progress {
                        case .downloading(let p): self?.transcribeState = .running("首次使用，正在下载识别模型…", p)
                        case .loading: self?.transcribeState = .running("正在加载模型…", nil)
                        case .transcribing(let p): self?.transcribeState = .running("正在识别…", p)
                        }
                    }
                }
                let subs = segments.map { Subtitle(start: $0.start, end: $0.end, text: $0.text) }
                self?.store.perform { $0.replaceSubtitles(subs) }
                self?.transcribeState = subs.isEmpty ? .failed("没有识别到语音") : .idle
            } catch {
                self?.transcribeState = .failed(error.localizedDescription)
            }
        }
    }

    // MARK: 键盘

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if NSApp.keyWindow?.firstResponder is NSText { return event }
            if event.modifierFlags.intersection([.command, .control, .option]).isEmpty == false { return event }
            return MainActor.assumeIsolated {
                switch event.keyCode {
                case 49: self.togglePlay(); return nil // 空格
                case 51, 117: self.deleteSelection(); return nil // Delete
                case 123: self.step(frames: event.modifierFlags.contains(.shift) ? -10 : -1); return nil
                case 124: self.step(frames: event.modifierFlags.contains(.shift) ? 10 : 1); return nil
                default: return event
                }
            }
        }
    }
}
