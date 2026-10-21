import Foundation

public enum EditLimits {
    public static let minClipDuration = Time(seconds: 0.1)
    public static let defaultImageDuration = Time(seconds: 3)
    public static let speedRange: ClosedRange<Double> = 0.25...4
    public static let defaultSubtitleDuration = Time(seconds: 2)
}

extension Project {
    // MARK: 主轨

    @discardableResult
    public mutating func appendToMain(assetID: UUID) -> UUID? {
        insertIntoMain(assetID: assetID, at: mainTrack.count)
    }

    @discardableResult
    public mutating func insertIntoMain(assetID: UUID, at index: Int) -> UUID? {
        guard let asset = asset(id: assetID) else { return nil }
        let length: Time
        switch asset.kind {
        case .video: length = asset.duration
        case .image: length = EditLimits.defaultImageDuration
        case .audio: return nil
        }
        guard length >= EditLimits.minClipDuration else { return nil }
        let clip = VideoClip(assetID: assetID, sourceIn: .zero, sourceOut: length)
        mainTrack.insert(clip, at: min(max(0, index), mainTrack.count))
        return clip.id
    }

    /// 在时间线时间 t 处分割主轨片段，返回后半段的新 id。
    @discardableResult
    public mutating func splitMain(at t: Time) -> UUID? {
        let layout = TimelineLayout(project: self)
        guard let index = layout.clipIndex(at: t) else { return nil }
        let placement = layout.placements[index]
        let offset = t - placement.start
        guard offset >= EditLimits.minClipDuration, placement.end - t >= EditLimits.minClipDuration else { return nil }
        var first = mainTrack[index]
        let splitPoint = first.sourceIn + offset * first.speed
        var second = first
        second.id = UUID()
        second.sourceIn = splitPoint
        first.sourceOut = splitPoint
        mainTrack[index] = first
        mainTrack.insert(second, at: index + 1)
        return second.id
    }

    public mutating func removeMain(id: UUID) {
        mainTrack.removeAll { $0.id == id }
        transitions[id] = nil
    }

    public mutating func moveMain(id: UUID, to newIndex: Int) {
        guard let from = mainTrack.firstIndex(where: { $0.id == id }) else { return }
        let clip = mainTrack.remove(at: from)
        mainTrack.insert(clip, at: min(max(0, newIndex), mainTrack.count))
    }

    public mutating func trimMain(id: UUID, sourceIn: Time, sourceOut: Time) {
        guard let i = mainTrack.firstIndex(where: { $0.id == id }) else { return }
        let upper = assetUpperBound(mainTrack[i].assetID)
        var lo = sourceIn.clamped(.zero, upper)
        var hi = sourceOut.clamped(.zero, upper)
        if hi - lo < EditLimits.minClipDuration {
            hi = lo + EditLimits.minClipDuration
            if hi > upper {
                hi = upper
                lo = upper - EditLimits.minClipDuration
            }
        }
        mainTrack[i].sourceIn = lo
        mainTrack[i].sourceOut = hi
    }

    public mutating func setSpeed(id: UUID, _ speed: Double) {
        updateMain(id: id) { $0.speed = min(max(speed, EditLimits.speedRange.lowerBound), EditLimits.speedRange.upperBound) }
    }

    public mutating func updateMain(id: UUID, _ body: (inout VideoClip) -> Void) {
        guard let i = mainTrack.firstIndex(where: { $0.id == id }) else { return }
        body(&mainTrack[i])
    }

    public mutating func setTransition(_ transition: Transition?, before clipID: UUID) {
        guard let i = mainTrack.firstIndex(where: { $0.id == clipID }), i > 0 else { return }
        transitions[clipID] = transition
    }

    public mutating func applyTransitionToAll(_ transition: Transition?) {
        transitions = [:]
        guard let transition else { return }
        for clip in mainTrack.dropFirst() { transitions[clip.id] = transition }
    }

    public mutating func applyFilterToAll(_ filter: FilterSettings) {
        for i in mainTrack.indices { mainTrack[i].filter = filter }
    }

    /// 粘贴调色到指定片段。
    public mutating func applyFilter(_ filter: FilterSettings, to ids: Set<UUID>) {
        for i in mainTrack.indices where ids.contains(mainTrack[i].id) { mainTrack[i].filter = filter }
    }

    /// 去掉所有调色的副本（对比原图用），其他设置不变。
    public func withoutGrading() -> Project {
        var p = self
        for i in p.mainTrack.indices { p.mainTrack[i].filter = FilterSettings() }
        return p
    }

    // MARK: 音乐

    @discardableResult
    public mutating func addMusic(assetID: UUID, at start: Time) -> UUID? {
        guard let asset = asset(id: assetID), asset.kind == .audio || (asset.kind == .video && asset.hasAudio),
              asset.duration >= EditLimits.minClipDuration else { return nil }
        let clip = AudioClip(assetID: assetID, start: Time.max(.zero, start), sourceIn: .zero, sourceOut: asset.duration)
        musicTrack.append(clip)
        musicTrack.sort { $0.start < $1.start }
        return clip.id
    }

    @discardableResult
    public mutating func splitMusic(id: UUID, at t: Time) -> UUID? {
        guard let i = musicTrack.firstIndex(where: { $0.id == id }) else { return nil }
        var first = musicTrack[i]
        let offset = t - first.start
        guard offset >= EditLimits.minClipDuration, first.end - t >= EditLimits.minClipDuration else { return nil }
        var second = first
        second.id = UUID()
        second.start = t
        second.sourceIn = first.sourceIn + offset
        second.fadeIn = .zero
        first.sourceOut = first.sourceIn + offset
        first.fadeOut = .zero
        musicTrack[i] = first
        musicTrack.insert(second, at: i + 1)
        return second.id
    }

    public mutating func removeMusic(id: UUID) {
        musicTrack.removeAll { $0.id == id }
    }

    public mutating func updateMusic(id: UUID, _ body: (inout AudioClip) -> Void) {
        guard let i = musicTrack.firstIndex(where: { $0.id == id }) else { return }
        body(&musicTrack[i])
        let upper = assetUpperBound(musicTrack[i].assetID)
        musicTrack[i].start = Time.max(.zero, musicTrack[i].start)
        musicTrack[i].sourceIn = musicTrack[i].sourceIn.clamped(.zero, upper)
        musicTrack[i].sourceOut = musicTrack[i].sourceOut.clamped(musicTrack[i].sourceIn + EditLimits.minClipDuration, upper)
        let half = musicTrack[i].duration / 2
        musicTrack[i].fadeIn = musicTrack[i].fadeIn.clamped(.zero, half)
        musicTrack[i].fadeOut = musicTrack[i].fadeOut.clamped(.zero, half)
        musicTrack.sort { $0.start < $1.start }
    }

    // MARK: 字幕

    @discardableResult
    public mutating func addSubtitle(at t: Time, text: String, duration: Time = EditLimits.defaultSubtitleDuration) -> UUID {
        let sub = Subtitle(start: Time.max(.zero, t), end: Time.max(.zero, t) + duration, text: text)
        subtitles.append(sub)
        subtitles.sort { $0.start < $1.start }
        return sub.id
    }

    public mutating func updateSubtitle(id: UUID, _ body: (inout Subtitle) -> Void) {
        guard let i = subtitles.firstIndex(where: { $0.id == id }) else { return }
        body(&subtitles[i])
        subtitles[i].start = Time.max(.zero, subtitles[i].start)
        if subtitles[i].end - subtitles[i].start < EditLimits.minClipDuration {
            subtitles[i].end = subtitles[i].start + EditLimits.minClipDuration
        }
        subtitles.sort { $0.start < $1.start }
    }

    public mutating func removeSubtitle(id: UUID) {
        subtitles.removeAll { $0.id == id }
    }

    public mutating func removeAllSubtitles() {
        subtitles.removeAll()
    }

    /// 与下一条合并：时间取两条的并集，文字相连（两侧都是拉丁字母时补空格）。
    @discardableResult
    public mutating func mergeSubtitleWithNext(id: UUID) -> Bool {
        guard let i = subtitles.firstIndex(where: { $0.id == id }), i + 1 < subtitles.count else { return false }
        let next = subtitles.remove(at: i + 1)
        let a = subtitles[i].text, b = next.text
        let needsSpace = (a.last?.isASCII == true && a.last?.isLetter == true) && (b.first?.isASCII == true && b.first?.isLetter == true)
        subtitles[i].text = a + (needsSpace ? " " : "") + b
        subtitles[i].end = Time.max(subtitles[i].end, next.end)
        return true
    }

    /// 在 t 处一分为二，文字按时间比例切开（之后再逐条校对）。返回后一条的 id。
    @discardableResult
    public mutating func splitSubtitle(id: UUID, at t: Time) -> UUID? {
        guard let i = subtitles.firstIndex(where: { $0.id == id }) else { return nil }
        var first = subtitles[i]
        guard t - first.start >= EditLimits.minClipDuration, first.end - t >= EditLimits.minClipDuration else { return nil }
        let chars = Array(first.text)
        let ratio = (t - first.start).seconds / first.duration.seconds
        let cut = chars.count < 2 ? chars.count : min(chars.count - 1, max(1, Int((Double(chars.count) * ratio).rounded())))
        var second = first
        second.id = UUID()
        second.start = t
        second.text = String(chars[cut...]).trimmingCharacters(in: .whitespaces)
        first.end = t
        first.text = String(chars[..<cut]).trimmingCharacters(in: .whitespaces)
        subtitles[i] = first
        subtitles.insert(second, at: i + 1)
        return second.id
    }

    public mutating func replaceSubtitles(_ subs: [Subtitle]) {
        subtitles = subs.sorted { $0.start < $1.start }
    }

    // MARK: 素材

    public var hasHDRAssets: Bool { assets.contains { $0.hdr != nil } }

    /// 追加素材（按 id 去重）。时间线为空时画幅与帧率跟随第一个视频 / 图片；色彩模式跟随素材。
    public mutating func addAssets(_ newAssets: [MediaAsset]) {
        for asset in newAssets where !assets.contains(where: { $0.id == asset.id }) {
            assets.append(asset)
        }
        if formatIsAutomatic, mainTrack.isEmpty, let first = newAssets.first(where: { $0.kind != .audio && $0.width > 0 }) {
            aspect = AspectRatio.nearest(width: first.width, height: first.height)
            if first.kind == .video { frameRate = Self.nearestFrameRate(first.frameRate) }
            formatIsAutomatic = false
        }
        updateAutomaticColorMode()
    }

    /// 从素材库删除素材及其在时间线上的所有片段。
    public mutating func removeAsset(id: UUID) {
        for clip in mainTrack where clip.assetID == id { removeMain(id: clip.id) }
        musicTrack.removeAll { $0.assetID == id }
        assets.removeAll { $0.id == id }
        updateAutomaticColorMode()
    }

    private mutating func updateAutomaticColorMode() {
        if colorModeIsAutomatic { colorMode = hasHDRAssets ? .hdr : .sdr }
    }

    /// 用户手动设置色彩模式，之后不再自动切换。
    public mutating func setColorMode(_ mode: ColorMode) {
        colorMode = mode
        colorModeIsAutomatic = false
    }

    /// 用户手动设置画幅 / 帧率，之后不再跟随素材。
    public mutating func setAspect(_ value: AspectRatio) {
        aspect = value
        formatIsAutomatic = false
    }

    public mutating func setFrameRate(_ value: Int) {
        frameRate = value
        formatIsAutomatic = false
    }

    /// 素材帧率 → 最接近的工程帧率（23.976→24，29.97→30，高帧率慢动作→60）。
    public static func nearestFrameRate(_ fps: Double) -> Int {
        guard fps > 0 else { return 30 }
        return frameRates.min { abs(Double($0) - fps) < abs(Double($1) - fps) } ?? 30
    }

    public func missingAssets(fileExists: (String) -> Bool) -> [MediaAsset] {
        assets.filter { !fileExists($0.path) }
    }

    public mutating func relinkAsset(id: UUID, to path: String, bookmark: Data?) {
        guard let i = assets.firstIndex(where: { $0.id == id }) else { return }
        assets[i].path = path
        assets[i].name = (path as NSString).lastPathComponent
        assets[i].bookmark = bookmark
    }

    /// 片段源区间上限：图片不限（取很大值），其余为素材时长。
    private func assetUpperBound(_ assetID: UUID) -> Time {
        guard let asset = asset(id: assetID) else { return .zero }
        return asset.kind == .image ? Time(seconds: 3600) : asset.duration
    }
}
