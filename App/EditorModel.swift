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

    var isRunning: Bool {
        if case .running = self { return true }
        return false
    }
}

/// 一个打开的工程：编辑状态、播放器、自动保存、导出与识别。
@Observable
@MainActor
final class EditorModel {
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
    /// 非错误的提示（如自动切换到 HDR）。
    var notice: String?
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

    /// 预览渲染短边：跟随预览区实际像素，渲染跟不上时降档（上限 previewCap）。
    private(set) var previewShortSide = 720
    @ObservationIgnored private var previewViewPixels: Double = 720
    @ObservationIgnored private var previewCap = PreviewQuality.tiers.last!
    @ObservationIgnored private var qualityTask: Task<Void, Never>?

    var previewSize: CGSize { RenderSize.size(aspect: project.aspect, shortSide: previewShortSide) }

    /// 预览区尺寸变化（短边，物理像素）。
    func previewViewChanged(shortSidePixels: Double) {
        previewViewPixels = shortSidePixels
        applyPreviewQuality()
    }

    private func applyPreviewQuality() {
        let side = PreviewQuality.shortSide(viewPixels: previewViewPixels, cap: previewCap)
        guard side != previewShortSide else { return }
        previewShortSide = side
        scheduleRebuild()
    }

    /// 播放时每 2 秒检查渲染耗时，跟不上就降一档。
    private func startQualityMonitor() {
        RenderTimer.preview.reset()
        qualityTask?.cancel()
        qualityTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard let self, self.isPlaying else { return }
                guard let avg = RenderTimer.preview.averageMs else { continue }
                let cap = PreviewQuality.capAfterMeasuring(cap: min(self.previewCap, self.previewShortSide),
                                                           averageRenderMs: avg, frameRate: self.project.frameRate)
                if cap < self.previewShortSide {
                    self.previewCap = cap
                    self.applyPreviewQuality()
                }
                RenderTimer.preview.reset()
            }
        }
    }

    /// 当前播放项创建时使用的输出动态范围。
    @ObservationIgnored private var itemOutput: DynamicRangeOutput = .sdr

    /// HDR 工程以 HLG 预览，在支持 EDR 的屏幕上显示真实亮度。
    var previewOutput: DynamicRangeOutput { project.colorMode == .hdr ? .hlg : .sdr }

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
        let output = previewOutput
        if let built, let item = player.currentItem, built.canUpdateInPlace(project: project, from: itemOutput, to: output) {
            itemOutput = output
            item.videoComposition = built.makeVideoComposition(project: renderProject(project), renderSize: size, output: output)
            item.audioMix = built.makeAudioMix(project: project)
            if !isPlaying { seek(to: playhead) }
            return
        }
        do {
            let next = try await CompositionBuilder.build(project: project, renderSize: size)
            guard !Task.isCancelled, project == store.project else { return }
            let item = AVPlayerItem(asset: next.composition)
            item.videoComposition = next.makeVideoComposition(project: renderProject(project), renderSize: size, output: output)
            itemOutput = output
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
            Log.project.error("预览构建失败：\(error.localizedDescription, privacy: .public)")
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
            startQualityMonitor()
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

    /// 缩放时保持在屏幕上不动的时刻（鼠标处或播放头），由时间线读取后清空。
    @ObservationIgnored var zoomAnchor: Time?
    /// 下次缩放后滚回开头（适应窗口用）。
    @ObservationIgnored var zoomScrollsToStart = false
    /// 时间线可视宽度，由时间线视图写入。
    @ObservationIgnored var timelineViewportWidth: Double = 800

    /// 菜单 / 滑块缩放：以播放头为锚点。
    func zoom(by factor: Double) {
        zoom(by: factor, anchor: playhead)
    }

    /// 适应窗口：整段时长铺满时间线并滚回开头。
    func zoomToFit() {
        zoomScrollsToStart = true
        pointsPerSecond = TimelineZoom.fit(duration: duration, viewportWidth: timelineViewportWidth, leading: 16, trailing: 60)
    }

    func zoom(by factor: Double, anchor: Time) {
        zoomAnchor = anchor
        pointsPerSecond = TimelineZoom.clamped(pointsPerSecond * factor)
    }

    // MARK: 编辑

    func splitAtPlayhead() {
        let t = playhead
        if case .subtitle(let id) = selection, let sub = project.subtitle(id: id), sub.start < t, t < sub.end {
            var newID: UUID?
            store.perform { newID = $0.splitSubtitle(id: id, at: t) }
            if let newID { selection = .subtitle(newID) }
            return
        }
        if case .music(let id) = selection, let clip = project.music(id: id), clip.start < t, t < clip.end {
            store.perform { _ = $0.splitMusic(id: id, at: t) }
            return
        }
        var newID: UUID?
        store.perform { newID = $0.splitMain(at: t) }
        if let newID { selection = .video(newID) }
    }

    // MARK: 字幕编辑

    /// 请求清空全部字幕（弹确认框）。
    var confirmClearSubtitles = false

    func clearSubtitles() {
        store.perform { $0.removeAllSubtitles() }
        if case .subtitle = selection { selection = nil }
    }

    func mergeSubtitleWithNext(_ id: UUID) {
        store.perform { $0.mergeSubtitleWithNext(id: id) }
        selection = .subtitle(id)
    }

    func removeSubtitle(_ id: UUID) {
        store.perform { $0.removeSubtitle(id: id) }
        if selection == .subtitle(id) { selection = nil }
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

    // MARK: 调色工作流

    /// 复制的调色（复制 / 粘贴调色）。
    var copiedFilter: FilterSettings?
    /// 按住“对比”时预览不带调色的原图。
    var comparingOriginal = false {
        didSet { if comparingOriginal != oldValue { scheduleRebuild(immediate: true) } }
    }

    private func renderProject(_ p: Project) -> Project {
        comparingOriginal ? p.withoutGrading() : p
    }

    func copyGrade() {
        guard let clip = selectedClip else { return }
        copiedFilter = clip.filter
        notice = "已复制调色。选中其他片段后按 ⌥⌘V 粘贴。"
    }

    func pasteGrade() {
        guard let filter = copiedFilter, let clip = selectedClip else { return }
        store.perform { $0.applyFilter(filter, to: [clip.id]) }
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
                Log.media.error("无法导入 \(url.lastPathComponent, privacy: .public)：\(error.localizedDescription, privacy: .public)")
            }
        }
        let at = playhead
        let wasHDR = project.colorMode == .hdr
        let wasAutoFormat = project.formatIsAutomatic
        store.perform { p in
            p.addAssets(assets)
            guard addToTimeline else { return }
            for asset in assets {
                switch asset.kind {
                case .video, .image: p.appendToMain(assetID: asset.id)
                case .audio: p.addMusic(assetID: asset.id, at: at)
                }
            }
        }
        if !failed.isEmpty { errorMessage = "以下文件无法导入：\(failed.joined(separator: "、"))" }
        var notes: [String] = []
        if wasAutoFormat, !project.formatIsAutomatic {
            notes.append("已按素材设置画面为 \(project.aspect.displayName) · \(project.frameRate) fps")
        }
        if !wasHDR, project.colorMode == .hdr {
            notes.append("检测到 HDR 素材，工程已切换为 HDR，预览与导出保留高光细节")
        }
        if !notes.isEmpty { notice = notes.joined(separator: "；") + "。可在右侧工程设置中修改。" }
    }

    /// 从素材库删除素材（连同时间线上用到它的片段）。
    func removeAsset(_ asset: MediaAsset) {
        let used = project.mainTrack.contains { $0.assetID == asset.id } || project.musicTrack.contains { $0.assetID == asset.id }
        if used {
            let alert = NSAlert()
            alert.messageText = "删除“\(asset.name)”？"
            alert.informativeText = "时间线上用到这个素材的片段也会一起删除。可以用 ⌘Z 撤销。"
            alert.addButton(withTitle: "删除")
            alert.addButton(withTitle: "取消")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        store.perform { $0.removeAsset(id: asset.id) }
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
            Log.project.error("保存失败：\(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: 导出

    func export(settings: ExportSettings, to url: URL) {
        exportState = .running(0)
        let project = store.project
        let started = Date()
        Log.export.info("开始导出 \(settings.shortSide)p \(settings.frameRate)fps \(settings.dynamicRange.rawValue) \(settings.effectiveCodec.rawValue)")
        exportTask = Task { [weak self] in
            do {
                try await Exporter().export(project: project, settings: settings, to: url) { p in
                    Task { @MainActor in
                        if case .running = self?.exportState { self?.exportState = .running(p) }
                    }
                }
                self?.exportState = .done(url)
                Log.export.info("导出完成，用时 \(Date().timeIntervalSince(started), format: .fixed(precision: 1)) 秒")
            } catch is CancellationError {
                self?.exportState = .idle
                Log.export.info("导出已取消")
            } catch {
                self?.exportState = .failed(error.localizedDescription)
                Log.export.error("导出失败：\(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func cancelExport() {
        exportTask?.cancel()
        exportTask = nil
        exportState = .idle
    }

    // MARK: 字幕识别

    func transcribe(language: TranscribeLanguage, original: Bool, music: Bool) {
        if case .running = transcribeState { return }
        transcribeState = .running("正在提取音频…", nil)
        let project = store.project
        Task { [weak self] in
            do {
                let samples = try await AudioExtractor.samples(project: project, original: original, music: music)
                guard !samples.isEmpty else {
                    self?.transcribeState = .failed(music ? "所选的声音来源里没有声音，无法识别" : "主轨视频没有声音，无法识别")
                    return
                }
                let segments = try await WhisperKitTranscriber.shared.transcribe(samples: samples, language: language) { progress in
                    Task { @MainActor in
                        switch progress {
                        case .downloading(let p): self?.transcribeState = .running("首次使用，正在下载识别模型…", p)
                        case .loading: self?.transcribeState = .running("正在加载模型…（首次加载需要一两分钟）", nil)
                        case .transcribing(let p): self?.transcribeState = .running("正在识别…", p)
                        }
                    }
                }
                let subs = segments.map { Subtitle(start: $0.start, end: $0.end, text: $0.text) }
                self?.store.perform { $0.replaceSubtitles(subs) }
                self?.transcribeState = subs.isEmpty ? .failed("没有识别到语音") : .idle
                Log.transcribe.info("识别完成：\(subs.count) 条字幕")
            } catch {
                self?.transcribeState = .failed(error.localizedDescription)
                Log.transcribe.error("识别失败：\(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: 键盘

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if NSApp.keyWindow?.firstResponder is NSText { return event }
            if event.modifierFlags.intersection([.command, .control, .option]).isEmpty == false { return event }
            let keyCode = event.keyCode
            let big = event.modifierFlags.contains(.shift)
            let handled = MainActor.assumeIsolated { () -> Bool in
                switch keyCode {
                case 49: self.togglePlay() // 空格
                case 51, 117: self.deleteSelection() // Delete
                case 123: self.step(frames: big ? -10 : -1)
                case 124: self.step(frames: big ? 10 : 1)
                default: return false
                }
                return true
            }
            return handled ? nil : event
        }
    }
}
