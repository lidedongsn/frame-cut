import Foundation

/// 字幕跟随主轨：把字幕的时间线时间换算成「片段 + 源时间」，编辑后再换算回新的时间线时间。
extension Project {
    /// 主轨编辑（from → self）后重新定位字幕。字幕取自 from，不是 self。
    func subtitlesFollowingMain(from old: Project) -> [Subtitle] {
        let oldLayout = TimelineLayout(project: old)
        let newLayout = TimelineLayout(project: self)
        let endShift = newLayout.duration - oldLayout.duration
        let oldIDs = Set(old.mainTrack.map(\.id))

        /// 时间线时间 → 新时间线时间。atEnd：取以 t 结束的片段（字幕结束点落在片段交界时归前一个片段）。
        /// 返回 (时间, 片段 id, 是否被夹到片段边缘)；片段已删除时为 nil。
        func map(_ t: Time, atEnd: Bool) -> (time: Time, clip: UUID?, clamped: Bool)? {
            guard t < oldLayout.duration || (atEnd && t == oldLayout.duration), !oldLayout.placements.isEmpty else {
                return (t + endShift, nil, false)
            }
            let index = atEnd ? oldLayout.placements.lastIndex { $0.start < t } : oldLayout.clipIndex(at: t)
            guard let index else { return (t, nil, false) }
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
            return (time, newClip.id, clampedSource != source)
        }

        func placement(of id: UUID?) -> ClipPlacement? {
            guard let id, let i = mainTrack.firstIndex(where: { $0.id == id }) else { return nil }
            return newLayout.placements[i]
        }

        var result: [Subtitle] = []
        for var sub in old.subtitles {
            let start = map(sub.start, atEnd: false)
            let end = map(sub.end, atEnd: true)
            var newStart: Time
            var newEnd: Time
            switch (start, end) {
            case (nil, nil):
                continue
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
                if s.clamped && e.clamped && s.clip == e.clip && newEnd - newStart < EditLimits.minClipDuration { continue }
            }
            guard newEnd - newStart >= EditLimits.minClipDuration else { continue }
            sub.start = Time.max(.zero, newStart)
            sub.end = newEnd
            result.append(sub)
        }
        return result.sorted { $0.start < $1.start }
    }
}
