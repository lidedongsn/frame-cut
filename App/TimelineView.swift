import FCCore
import FCMedia
import SwiftUI

private enum TL {
    static let leading: CGFloat = 16
    static let ruler: CGFloat = 26
    static let main: CGFloat = 70
    static let music: CGFloat = 44
    static let subtitle: CGFloat = 30
    static let gap: CGFloat = 8
    static let handle: CGFloat = 8

    static var mainY: CGFloat { ruler + gap }
    static var musicY: CGFloat { mainY + main + gap }
    static var subtitleY: CGFloat { musicY + music + gap }
    static var height: CGFloat { subtitleY + subtitle + gap }
}

/// 时间线：时间尺、主视频轨、音乐轨、字幕轨、播放头。
struct TimelineView: View {
    @Bindable var model: EditorModel
    @State private var scrollX: CGFloat = 0
    @State private var viewportWidth: CGFloat = 800

    private var pps: CGFloat { CGFloat(model.pointsPerSecond) }
    private func x(_ t: Time) -> CGFloat { TL.leading + CGFloat(t.seconds) * pps }
    private func time(_ x: CGFloat) -> Time { Time(seconds: max(0, Double((x - TL.leading) / pps))) }

    var body: some View {
        GeometryReader { geo in
            ScrollViewReader { proxy in
                ScrollView([.horizontal, .vertical]) {
                    let width = max(geo.size.width, x(model.duration) + 400)
                    ZStack(alignment: .topLeading) {
                        // 捏合 / ⌘⌥+滚轮缩放，并保持锚点位置
                        ZoomEventCatcher(model: model, pointsPerSecond: model.pointsPerSecond)
                            .frame(width: width, height: max(geo.size.height, TL.height))
                            .allowsHitTesting(false)

                        // 背景：点击 / 拖动定位播放头，取消选择
                        Color.clear
                            .frame(width: width, height: max(geo.size.height, TL.height))
                            .contentShape(Rectangle())
                            .gesture(DragGesture(minimumDistance: 0)
                                .onChanged { v in
                                    if v.translation == .zero { model.selection = nil }
                                    model.seek(to: time(v.location.x))
                                })

                        RulerView(pps: pps, width: width)
                            .frame(width: width, height: TL.ruler)
                            .gesture(DragGesture(minimumDistance: 0).onChanged { model.seek(to: time($0.location.x)) })

                        trackBackground(y: TL.mainY, height: TL.main, width: width)
                        trackBackground(y: TL.musicY, height: TL.music, width: width)
                        trackBackground(y: TL.subtitleY, height: TL.subtitle, width: width)

                        mainTrack(width: width)
                        musicTrack
                        subtitleTrack

                        PlayheadView(height: max(geo.size.height, TL.height))
                            .offset(x: x(model.playhead) - 6)
                            .gesture(DragGesture().onChanged { v in
                                model.seek(to: time(v.location.x))
                            })

                        Color.clear.frame(width: 1, height: 1)
                            .offset(x: x(model.playhead))
                            .id("playhead")
                    }
                    .frame(width: width, height: max(geo.size.height, TL.height), alignment: .topLeading)
                    .background(GeometryReader { g in
                        Color.clear.preference(key: ScrollXKey.self, value: -g.frame(in: .named("timeline")).minX)
                    })
                }
                .coordinateSpace(name: "timeline")
                .onPreferenceChange(ScrollXKey.self) { scrollX = $0 }
                .onAppear { viewportWidth = geo.size.width; model.timelineViewportWidth = geo.size.width }
                .onChange(of: geo.size.width) { _, w in viewportWidth = w; model.timelineViewportWidth = w }
                .onChange(of: model.playhead) { _, t in
                    guard model.isPlaying else { return }
                    let px = x(t)
                    if px > scrollX + viewportWidth * 0.9 || px < scrollX {
                        proxy.scrollTo("playhead", anchor: UnitPoint(x: 0.1, y: 0))
                    }
                }
            }
        }
        .background(Theme.window)
        .onDrop(of: [.text], isTargeted: nil) { providers in
            handleAssetDrop(providers, atX: nil)
        }
    }

    private func trackBackground(y: CGFloat, height: CGFloat, width: CGFloat) -> some View {
        Rectangle()
            .fill(Color.white.opacity(0.025))
            .frame(width: width, height: height)
            .offset(y: y)
            .allowsHitTesting(false)
    }

    // MARK: 主轨

    @ViewBuilder
    private func mainTrack(width: CGFloat) -> some View {
        if model.project.mainTrack.isEmpty {
            Text("把素材拖到这里，或在左侧素材库双击添加")
                .font(.system(size: 12))
                .foregroundStyle(Theme.tertiary)
                .frame(width: min(width, 600), height: TL.main)
                .background(RoundedRectangle(cornerRadius: Theme.corner).strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4])).foregroundStyle(Theme.tertiary))
                .offset(x: TL.leading, y: TL.mainY)
                .allowsHitTesting(false)
        }
        ForEach(model.layout.placements, id: \.clipID) { placement in
            if let clip = model.project.mainClip(id: placement.clipID), let asset = model.project.asset(id: clip.assetID) {
                MainClipView(model: model, clip: clip, asset: asset, placement: placement, pps: pps)
                    .offset(x: x(placement.start), y: TL.mainY)
            }
        }
        ForEach(model.layout.placements.dropFirst(), id: \.clipID) { placement in
            TransitionMarker(model: model, placement: placement)
                .offset(x: x(placement.start + (placement.transitionIn?.duration ?? .zero) / 2) - 10, y: TL.mainY + TL.main / 2 - 10)
        }
    }

    private var musicTrack: some View {
        ForEach(model.project.musicTrack) { clip in
            if let asset = model.project.asset(id: clip.assetID) {
                MusicClipView(model: model, clip: clip, asset: asset, pps: pps)
                    .offset(x: x(clip.start), y: TL.musicY)
            }
        }
    }

    private var subtitleTrack: some View {
        ForEach(model.project.subtitles) { sub in
            SubtitleClipView(model: model, sub: sub, pps: pps)
                .offset(x: x(sub.start), y: TL.subtitleY)
        }
    }

    private func handleAssetDrop(_ providers: [NSItemProvider], atX: CGFloat?) -> Bool {
        for provider in providers {
            _ = provider.loadObject(ofClass: NSString.self) { obj, _ in
                guard let s = obj as? String, let id = AssetDrag.assetID(s) else { return }
                Task { @MainActor in
                    guard let asset = model.project.asset(id: id) else { return }
                    model.store.perform { p in
                        if asset.kind == .audio { p.addMusic(assetID: id, at: model.playhead) } else { p.appendToMain(assetID: id) }
                    }
                }
            }
        }
        return true
    }
}

// MARK: - 缩放

/// 接收触控板捏合与 ⌘/⌥+滚轮，按鼠标处时刻缩放；缩放后调整滚动位置，使锚点在屏幕上不动。
private struct ZoomEventCatcher: NSViewRepresentable {
    let model: EditorModel
    let pointsPerSecond: Double

    func makeCoordinator() -> Coordinator { Coordinator(model: model, pointsPerSecond: pointsPerSecond) }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.view = view
        context.coordinator.install()
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.pointsPerSecondChanged(to: pointsPerSecond)
    }

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    @MainActor
    final class Coordinator {
        let model: EditorModel
        weak var view: NSView?
        private var monitor: Any?
        private var lastPointsPerSecond: Double

        init(model: EditorModel, pointsPerSecond: Double) {
            self.model = model
            lastPointsPerSecond = pointsPerSecond
        }

        func install() {
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .magnify]) { [weak self] event in
                MainActor.assumeIsolated { self?.handle(event) ?? event }
            }
        }

        func uninstall() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            guard let view, event.window === view.window else { return event }
            let point = view.convert(event.locationInWindow, from: nil)
            guard view.visibleRect.contains(point) else { return event }
            let factor: Double
            switch event.type {
            case .magnify:
                factor = 1 + event.magnification
            case .scrollWheel where !event.modifierFlags.intersection([.command, .option]).isEmpty:
                let dy = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 8
                factor = TimelineZoom.factor(scrollDelta: dy)
            default:
                return event
            }
            // SwiftUI 内容坐标 y 向下，x 与时间线一致
            let anchor = Time(seconds: max(0, Double(point.x - TL.leading) / model.pointsPerSecond))
            model.zoom(by: factor, anchor: anchor)
            return nil
        }

        func pointsPerSecondChanged(to pps: Double) {
            guard pps != lastPointsPerSecond else { return }
            let old = lastPointsPerSecond
            lastPointsPerSecond = pps
            guard let scrollView = view?.enclosingScrollView else { return }
            let anchor = model.zoomAnchor ?? model.playhead
            model.zoomAnchor = nil
            let clip = scrollView.contentView
            let origin = model.zoomScrollsToStart ? 0
                : TimelineZoom.scrollOrigin(anchor: anchor, oldPointsPerSecond: old, newPointsPerSecond: pps,
                                            oldOrigin: Double(clip.bounds.origin.x), leading: Double(TL.leading))
            model.zoomScrollsToStart = false
            // 等 SwiftUI 按新宽度布局后再滚动
            DispatchQueue.main.async {
                clip.scroll(to: NSPoint(x: CGFloat(origin), y: clip.bounds.origin.y))
                scrollView.reflectScrolledClipView(clip)
            }
        }
    }
}

private struct ScrollXKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

// MARK: - 时间尺

private struct RulerView: View {
    let pps: CGFloat
    let width: CGFloat

    var body: some View {
        Canvas { ctx, size in
            let candidates: [Double] = [0.1, 0.25, 0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300, 600, 1200]
            let major = candidates.first { $0 * Double(pps) >= 80 } ?? 1800
            let minor = major / 5
            let ticksPerMajor = 5
            var i = 0
            while TL.leading + CGFloat(Double(i) * minor) * pps < size.width {
                let t = Double(i) * minor
                let x = TL.leading + CGFloat(t) * pps
                let isMajor = i % ticksPerMajor == 0
                var path = Path()
                path.move(to: CGPoint(x: x, y: size.height - (isMajor ? 10 : 5)))
                path.addLine(to: CGPoint(x: x, y: size.height))
                ctx.stroke(path, with: .color(Theme.tertiary), lineWidth: 1)
                if isMajor {
                    ctx.draw(Text(label(t, major: major)).font(.system(size: 9).monospacedDigit()).foregroundColor(Theme.secondary),
                             at: CGPoint(x: x + 3, y: 4), anchor: .topLeading)
                }
                i += 1
            }
        }
    }

    /// 主刻度为整秒时显示 mm:ss，否则带一位小数。
    private func label(_ t: Double, major: Double) -> String {
        let m = Int(t) / 60
        let s = t - Double(m * 60)
        return major >= 1 ? String(format: "%02d:%02d", m, Int(s.rounded())) : String(format: "%02d:%04.1f", m, s)
    }
}

private struct PlayheadView: View {
    let height: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            Path { p in
                p.move(to: .zero)
                p.addLine(to: CGPoint(x: 12, y: 0))
                p.addLine(to: CGPoint(x: 12, y: 8))
                p.addLine(to: CGPoint(x: 6, y: 14))
                p.addLine(to: CGPoint(x: 0, y: 8))
                p.closeSubpath()
            }
            .fill(Theme.playhead)
            .frame(width: 12, height: 14)
            Rectangle().fill(Theme.playhead).frame(width: 2, height: height - 14)
        }
        .frame(width: 12)
        .contentShape(Rectangle())
    }
}

// MARK: - 修剪手柄

private struct TrimHandle: View {
    let leading: Bool
    let onChange: (CGFloat) -> Void
    let onEnd: () -> Void

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(Color.white)
            .frame(width: TL.handle)
            .overlay(Rectangle().fill(Color.black.opacity(0.4)).frame(width: 2, height: 14))
            .contentShape(Rectangle())
            .onHover { inside in
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .named("timeline"))
                .onChanged { onChange($0.translation.width) }
                .onEnded { _ in onEnd() })
    }
}

// MARK: - 视频片段

private struct MainClipView: View {
    @Bindable var model: EditorModel
    let clip: VideoClip
    let asset: MediaAsset
    let placement: ClipPlacement
    let pps: CGFloat

    @State private var dragX: CGFloat = 0
    @State private var trimStart: (Time, Time)?

    private var selected: Bool { model.selection == .video(clip.id) }
    private var width: CGFloat { max(4, CGFloat(placement.duration.seconds) * pps) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ThumbnailStrip(asset: asset, clip: clip, width: width, height: TL.main, pps: pps)
            LinearGradient(colors: [.black.opacity(0.55), .clear], startPoint: .top, endPoint: .center)
                .allowsHitTesting(false)
            HStack(spacing: 4) {
                if clip.speed != 1 {
                    Text(String(format: "%.2gx", clip.speed)).font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 3).background(Theme.accent, in: RoundedRectangle(cornerRadius: 2)).foregroundStyle(.black)
                }
                if asset.hdr != nil { HDRBadge(small: true) }
                if clip.muted { Image(systemName: "speaker.slash.fill").font(.system(size: 9)) }
                if clip.filter.preset != .none { Image(systemName: "camera.filters").font(.system(size: 9)) }
                Text(placement.duration.displayString).font(.system(size: 9).monospacedDigit())
            }
            .foregroundStyle(.white)
            .padding(4)
            .frame(width: width, alignment: .leading)
            .clipped()
            .allowsHitTesting(false)
        }
        .frame(width: width, height: TL.main)
        .background(Theme.videoClip)
        .clipShape(RoundedRectangle(cornerRadius: Theme.corner))
        .overlay(RoundedRectangle(cornerRadius: Theme.corner).stroke(selected ? Color.white : Theme.border, lineWidth: selected ? 2 : 1))
        .overlay(alignment: .leading) { if selected { trimHandle(leading: true) } }
        .overlay(alignment: .trailing) { if selected { trimHandle(leading: false) } }
        .offset(x: dragX)
        .zIndex(dragX != 0 ? 10 : (selected ? 5 : 0))
        .opacity(dragX != 0 ? 0.85 : 1)
        .onTapGesture { model.selection = .video(clip.id) }
        .gesture(DragGesture(minimumDistance: 6, coordinateSpace: .named("timeline"))
            .onChanged { v in
                model.selection = .video(clip.id)
                dragX = v.translation.width
            }
            .onEnded { v in
                reorder(dropCenter: CGFloat(placement.start.seconds) * pps + width / 2 + v.translation.width)
                dragX = 0
            })
        .contextMenu {
            Button("在播放头处分割") { model.splitAtPlayhead() }
            Button(clip.muted ? "取消静音" : "静音") { model.store.perform { $0.updateMain(id: clip.id) { $0.muted.toggle() } } }
            Divider()
            Button("复制调色") { model.selection = .video(clip.id); model.copyGrade() }
            Button("粘贴调色") { model.selection = .video(clip.id); model.pasteGrade() }
                .disabled(model.copiedFilter == nil)
            Divider()
            Button("删除", role: .destructive) { model.store.perform { $0.removeMain(id: clip.id) } }
        }
    }

    private func trimHandle(leading: Bool) -> some View {
        TrimHandle(leading: leading) { dx in
            if trimStart == nil {
                trimStart = (clip.sourceIn, clip.sourceOut)
                model.store.beginCoalescing()
            }
            guard let (inT, outT) = trimStart else { return }
            let delta = Time(seconds: Double(dx / pps) * clip.speed)
            model.store.perform { p in
                if leading { p.trimMain(id: clip.id, sourceIn: inT + delta, sourceOut: outT) } else { p.trimMain(id: clip.id, sourceIn: inT, sourceOut: outT + delta) }
            }
        } onEnd: {
            trimStart = nil
            model.store.endCoalescing()
        }
    }

    /// 按拖放后片段中心点所在位置决定新顺序。
    private func reorder(dropCenter: CGFloat) {
        let placements = model.layout.placements
        var target = placements.count - 1
        for p in placements where p.clipID != clip.id {
            let center = CGFloat(p.start.seconds + p.duration.seconds / 2) * pps
            if dropCenter < center {
                target = p.index > placement.index ? p.index - 1 : p.index
                break
            }
        }
        if target != placement.index { model.store.perform { $0.moveMain(id: clip.id, to: target) } }
    }
}

private struct ThumbnailStrip: View {
    let asset: MediaAsset
    let clip: VideoClip
    let width: CGFloat
    let height: CGFloat
    let pps: CGFloat

    private var cellWidth: CGFloat {
        let aspect = asset.height > 0 ? CGFloat(asset.width) / CGFloat(asset.height) : 16 / 9
        return max(height * aspect, width / 40)
    }

    var body: some View {
        let count = max(1, Int((width / cellWidth).rounded(.up)))
        HStack(spacing: 0) {
            ForEach(0..<count, id: \.self) { i in
                let t = clip.sourceIn + Time(seconds: Double((CGFloat(i) + 0.5) * cellWidth / pps) * clip.speed)
                ThumbnailCell(url: asset.url, time: asset.kind == .image ? .zero : Time.min(t, clip.sourceOut), height: height, hdr: asset.hdr)
                    .frame(width: cellWidth, height: height)
                    .clipped()
            }
        }
        .frame(width: width, height: height, alignment: .leading)
        .clipped()
    }
}

private struct ThumbnailCell: View {
    let url: URL
    let time: Time
    let height: CGFloat
    let hdr: HDRFormat?
    @State private var image: CGImage?

    var body: some View {
        ZStack {
            if let image {
                Image(decorative: image, scale: 1).resizable().scaledToFill()
            }
        }
        .task(id: "\(url.path)|\(Int(time.seconds * 2))") {
            image = await Thumbnails.shared.thumbnail(url: url, time: time, maxHeight: height, hdr: hdr)
        }
    }
}

private struct TransitionMarker: View {
    @Bindable var model: EditorModel
    let placement: ClipPlacement

    private var selected: Bool { model.selection == .transition(placement.clipID) }

    var body: some View {
        Button {
            model.selection = .transition(placement.clipID)
        } label: {
            Image(systemName: placement.transitionIn == nil ? "plus" : "arrow.left.arrow.right")
                .font(.system(size: 9, weight: .bold))
                .frame(width: 20, height: 20)
                .background(RoundedRectangle(cornerRadius: 4).fill(placement.transitionIn == nil ? Color.black.opacity(0.6) : Theme.accent))
                .foregroundStyle(placement.transitionIn == nil ? Color.white : Color.black)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(selected ? Color.white : .clear, lineWidth: 2))
                .rotationEffect(.degrees(placement.transitionIn == nil ? 45 : 0))
        }
        .buttonStyle(.plain)
        .zIndex(20)
        .help(placement.transitionIn.map { "转场：\($0.kind.displayName)" } ?? "添加转场")
    }
}

// MARK: - 音乐片段

private struct MusicClipView: View {
    @Bindable var model: EditorModel
    let clip: AudioClip
    let asset: MediaAsset
    let pps: CGFloat

    @State private var peaks: [Float] = []
    @State private var dragStart: AudioClip?

    private var selected: Bool { model.selection == .music(clip.id) }
    private var width: CGFloat { max(4, CGFloat(clip.duration.seconds) * pps) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Canvas { ctx, size in
                guard !peaks.isEmpty else { return }
                let perSecond = 50.0
                let from = Int(clip.sourceIn.seconds * perSecond)
                let to = min(peaks.count, Int(clip.sourceOut.seconds * perSecond))
                guard to > from else { return }
                let step = max(1, Int(Double(to - from) / Double(size.width / 2)))
                var path = Path()
                var i = from
                while i < to {
                    let x = CGFloat(Double(i - from) / Double(to - from)) * size.width
                    let h = CGFloat(peaks[i...min(to - 1, i + step - 1)].max() ?? 0) * (size.height - 16)
                    path.addRect(CGRect(x: x, y: size.height - 4 - h, width: 1.2, height: h))
                    i += step
                }
                ctx.fill(path, with: .color(Color.white.opacity(0.45)))
            }
            HStack(spacing: 4) {
                Image(systemName: "music.note").font(.system(size: 9))
                Text(asset.name).font(.system(size: 10)).lineLimit(1)
            }
            .foregroundStyle(.white)
            .padding(4)
        }
        .frame(width: width, height: TL.music)
        .background(Theme.musicClip)
        .clipShape(RoundedRectangle(cornerRadius: Theme.corner))
        .overlay(RoundedRectangle(cornerRadius: Theme.corner).stroke(selected ? Color.white : Theme.border, lineWidth: selected ? 2 : 1))
        .overlay(alignment: .leading) { if selected { handle(leading: true) } }
        .overlay(alignment: .trailing) { if selected { handle(leading: false) } }
        .zIndex(selected ? 5 : 0)
        .onTapGesture { model.selection = .music(clip.id) }
        .gesture(DragGesture(minimumDistance: 4, coordinateSpace: .named("timeline"))
            .onChanged { v in
                begin()
                guard let s = dragStart else { return }
                let start = s.start + Time(seconds: Double(v.translation.width / pps))
                model.store.perform { $0.updateMusic(id: clip.id) { $0.start = start } }
            }
            .onEnded { _ in end() })
        .task(id: asset.path) { peaks = await WaveformProvider.shared.peaks(url: asset.url) }
        .contextMenu {
            Button("在播放头处分割") { model.selection = .music(clip.id); model.splitAtPlayhead() }
            Button("删除", role: .destructive) { model.store.perform { $0.removeMusic(id: clip.id) } }
        }
    }

    private func begin() {
        guard dragStart == nil else { return }
        dragStart = clip
        model.selection = .music(clip.id)
        model.store.beginCoalescing()
    }

    private func end() {
        dragStart = nil
        model.store.endCoalescing()
    }

    private func handle(leading: Bool) -> some View {
        TrimHandle(leading: leading) { dx in
            begin()
            guard let s = dragStart else { return }
            let delta = Time(seconds: Double(dx / pps))
            model.store.perform { p in
                p.updateMusic(id: clip.id) { c in
                    if leading {
                        let d = Time.max(Time.zero - s.sourceIn, Time.max(Time.zero - s.start, delta))
                        c.start = s.start + d
                        c.sourceIn = s.sourceIn + d
                    } else {
                        c.sourceOut = s.sourceOut + delta
                    }
                }
            }
        } onEnd: { end() }
    }
}

// MARK: - 字幕片段

private struct SubtitleClipView: View {
    @Bindable var model: EditorModel
    let sub: Subtitle
    let pps: CGFloat

    @State private var dragStart: Subtitle?

    private var selected: Bool { model.selection == .subtitle(sub.id) }
    private var width: CGFloat { max(4, CGFloat(sub.duration.seconds) * pps) }

    var body: some View {
        Text(sub.text)
            .font(.system(size: 10))
            .lineLimit(1)
            .padding(.horizontal, 5)
            .frame(width: width, height: TL.subtitle, alignment: .leading)
            .foregroundStyle(.white)
            .background(Theme.subtitleClip)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(selected ? Color.white : Theme.border, lineWidth: selected ? 2 : 1))
            .overlay(alignment: .leading) { if selected { handle(leading: true) } }
            .overlay(alignment: .trailing) { if selected { handle(leading: false) } }
            .zIndex(selected ? 5 : 0)
            .onTapGesture {
                model.selection = .subtitle(sub.id)
                model.seek(to: sub.start)
            }
            .gesture(DragGesture(minimumDistance: 4, coordinateSpace: .named("timeline"))
                .onChanged { v in
                    begin()
                    guard let s = dragStart else { return }
                    let d = Time.max(Time.zero - s.start, Time(seconds: Double(v.translation.width / pps)))
                    model.store.perform { $0.updateSubtitle(id: sub.id) { $0.start = s.start + d; $0.end = s.end + d } }
                }
                .onEnded { _ in end() })
            .help(sub.text)
    }

    private func begin() {
        guard dragStart == nil else { return }
        dragStart = sub
        model.selection = .subtitle(sub.id)
        model.store.beginCoalescing()
    }

    private func end() {
        dragStart = nil
        model.store.endCoalescing()
    }

    private func handle(leading: Bool) -> some View {
        TrimHandle(leading: leading) { dx in
            begin()
            guard let s = dragStart else { return }
            let delta = Time(seconds: Double(dx / pps))
            model.store.perform { p in
                p.updateSubtitle(id: sub.id) { c in
                    if leading { c.start = Time.min(s.end - EditLimits.minClipDuration, s.start + delta) } else { c.end = s.end + delta }
                }
            }
        } onEnd: { end() }
    }
}
