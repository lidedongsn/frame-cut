import Foundation

/// 字幕跟随主轨：把字幕的时间线时间换算成「片段 + 源时间」，编辑后再换算回新的时间线时间。
extension Project {
    /// 写入识别结果。subs 的时间按开始识别时的工程 base 计算。
    /// - 来自视频原声且识别期间剪辑过视频：换算到现在的时间线（与跟随开关无关，原声本来就随片段走）。
    /// - 跟随开关为自动时：只来自原声 → 跟随；只来自音频轨（旁白）→ 不跟随；两者都有 → 保持不变。
    public mutating func applyTranscription(_ subs: [Subtitle], recordedOn base: Project, original: Bool, music: Bool) {
        var recorded = base
        recorded.replaceSubtitles(subs)
        if original, TimelineLayout(project: self) != TimelineLayout(project: recorded) {
            subtitles = subtitlesFollowingMain(from: recorded)
        } else {
            replaceSubtitles(subs)
        }
        if subtitlesFollowIsAutomatic, original != music { subtitlesFollowMain = original }
    }

    /// 主轨编辑（from → self）后重新定位字幕。字幕取自 from，不是 self。
    public func subtitlesFollowingMain(from old: Project) -> [Subtitle] {
        // 原来没有片段时字幕没有可跟随的画面，保持原样
        guard !old.mainTrack.isEmpty else { return old.subtitles }
        let ranges = rangesFollowingMain(from: old, old.subtitles.map { ($0.start, $0.end) })
        return zip(old.subtitles, ranges).compactMap { sub, range in
            guard let range else { return nil }
            var sub = sub
            (sub.start, sub.end) = range
            return sub
        }.sorted { $0.start < $1.start }
    }

    /// 主轨编辑（from → self）后重新定位文字。文字总是跟随画面（地点、章节标注都属于它下面的片段）。
    public func textsFollowingMain(from old: Project) -> [TextClip] {
        guard !old.mainTrack.isEmpty else { return old.texts }
        let ranges = rangesFollowingMain(from: old, old.texts.map { ($0.start, $0.end) })
        return zip(old.texts, ranges).compactMap { clip, range in
            guard let range else { return nil }
            var clip = clip
            (clip.start, clip.end) = range
            return clip
        }.sorted { $0.start < $1.start }
    }

    /// 把 old 时间线上的时间段换算到 self 的时间线；所在画面被删掉或剪掉时为 nil。
    private func rangesFollowingMain(from old: Project, _ ranges: [(start: Time, end: Time)]) -> [(start: Time, end: Time)?] {
        let oldLayout = TimelineLayout(project: old)
        let newLayout = TimelineLayout(project: self)
        let endShift = newLayout.duration - oldLayout.duration
        let oldIDs = Set(old.mainTrack.map(\.id))

        /// 时间线时间 → 新时间线时间。atEnd：取以 t 结束的片段（字幕结束点落在片段交界时归前一个片段）。
        /// 返回 (时间, 片段 id)；源时间被剪掉时夹到片段边缘（整条被剪掉的字幕时长为 0，随后丢弃）；片段已删除时为 nil。
        func map(_ t: Time, atEnd: Bool) -> (time: Time, clip: UUID?)? {
            guard t < oldLayout.duration || (atEnd && t == oldLayout.duration), !oldLayout.placements.isEmpty else {
                return (t + endShift, nil)
            }
            let index = atEnd ? oldLayout.placements.lastIndex { $0.start < t } : oldLayout.clipIndex(at: t)
            guard let index else { return (t, nil) }
            let placement = oldLayout.placements[index]
            let clip = old.mainTrack[index]
            let source = clip.sourceIn + (t - placement.start) * clip.speed
            // 源时间仍在原片段内就用原片段；分割后可能落在分出来的后半段（同一素材、新 id）上。
            func contains(_ c: VideoClip) -> Bool {
                c.sourceIn <= source && (atEnd ? source <= c.sourceOut : source < c.sourceOut)
            }
            let same = mainTrack.firstIndex { $0.id == clip.id }
            let newIndex: Int
            if let same, contains(mainTrack[same]) {
                newIndex = same
            } else if let other = mainTrack.indices.first(where: { !oldIDs.contains(mainTrack[$0].id) && mainTrack[$0].assetID == clip.assetID && contains(mainTrack[$0]) }) {
                newIndex = other
            } else if let same {
                newIndex = same
            } else {
                return nil
            }
            let newClip = mainTrack[newIndex]
            let newPlacement = newLayout.placements[newIndex]
            let clampedSource = source.clamped(newClip.sourceIn, newClip.sourceOut)
            let time = newPlacement.start + (clampedSource - newClip.sourceIn) / newClip.speed
            return (time, newClip.id)
        }

        func placement(of id: UUID?) -> ClipPlacement? {
            guard let id, let i = mainTrack.firstIndex(where: { $0.id == id }) else { return nil }
            return newLayout.placements[i]
        }

        return ranges.map { range -> (start: Time, end: Time)? in
            let start = map(range.start, atEnd: false)
            let end = map(range.end, atEnd: true)
            var newStart: Time
            var newEnd: Time
            switch (start, end) {
            case (nil, nil):
                return nil
            case let (s?, nil):
                newStart = s.time
                newEnd = placement(of: s.clip)?.end ?? s.time
            case let (nil, e?):
                newStart = placement(of: e.clip)?.start ?? e.time
                newEnd = e.time
            case let (s?, e?):
                newStart = s.time
                newEnd = e.time
                // 跨两个片段且顺序被调换：只保留开头所在片段那部分
                if newEnd <= newStart, s.clip != e.clip { newEnd = placement(of: s.clip)?.end ?? newStart }
            }
            guard newEnd - newStart >= EditLimits.minClipDuration else { return nil }
            return (Time.max(.zero, newStart), newEnd)
        }
    }
}
