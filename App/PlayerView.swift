import AVFoundation
import FCCore
import SwiftUI

/// 预览区：画面 + 播放控制。
struct PlayerPanel: View {
    @Bindable var model: EditorModel
    @Environment(\.displayScale) private var displayScale

    private var hasGrading: Bool { model.project.mainTrack.contains { !$0.filter.isIdentity } }

    private func reportSize(_ size: CGSize) {
        model.previewViewChanged(shortSidePixels: Double(min(size.width, size.height) * displayScale))
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Color.black
                if model.project.mainTrack.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "film.stack").font(.system(size: 36)).foregroundStyle(Theme.tertiary)
                        Text("把视频或照片拖进来开始剪辑").foregroundStyle(Theme.secondary)
                        Button("导入素材…") { model.importPanel(addToTimeline: true) }
                            .buttonStyle(PanelButtonStyle(prominent: true))
                    }
                } else {
                    PlayerLayerView(player: model.player)
                        .aspectRatio(model.project.aspect.ratio, contentMode: .fit)
                        .overlay(alignment: .topLeading) {
                            if model.comparingOriginal {
                                Text("原图").font(.system(size: 11, weight: .semibold))
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(Color.black.opacity(0.6), in: Capsule())
                                    .foregroundStyle(.white)
                                    .padding(8)
                            }
                        }
                        .overlay {
                            GeometryReader { g in
                                SubtitleOverlay(model: model, canvas: g.size)
                            }
                            .coordinateSpace(name: "subtitleCanvas")
                        }
                        // 预览渲染分辨率跟随画面实际大小（物理像素）
                        .background(GeometryReader { g in
                            Color.clear
                                .onAppear { reportSize(g.size) }
                                .onChange(of: g.size) { _, size in reportSize(size) }
                        })
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture { model.togglePlay() }

            HStack(spacing: 18) {
                Text(model.playhead.displayString)
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(Theme.accent)
                    .frame(width: 96, alignment: .trailing)
                Button { model.step(frames: -1) } label: { Image(systemName: "backward.frame.fill") }
                    .buttonStyle(.plain).help("上一帧 ←")
                Button { model.togglePlay() } label: {
                    Image(systemName: model.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 18))
                }
                .buttonStyle(.plain)
                .help("播放 / 暂停（空格）")
                Button { model.step(frames: 1) } label: { Image(systemName: "forward.frame.fill") }
                    .buttonStyle(.plain).help("下一帧 →")
                Text(model.duration.displayString)
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(Theme.secondary)
                    .frame(width: 96, alignment: .leading)
            }
            .foregroundStyle(Theme.text)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .overlay(alignment: .trailing) {
                if hasGrading { CompareButton(model: model).padding(.trailing, 14) }
            }
            .disabled(model.duration == .zero)
        }
        .background(Theme.window)
    }
}

/// 按住显示原图，松开恢复调色效果。
private struct CompareButton: View {
    @Bindable var model: EditorModel

    var body: some View {
        Label("对比", systemImage: "square.split.2x1")
            .font(.system(size: 11))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(model.comparingOriginal ? Theme.accent.opacity(0.3) : Theme.raised, in: RoundedRectangle(cornerRadius: 5))
            .foregroundStyle(model.comparingOriginal ? Theme.accent : Theme.secondary)
            .contentShape(Rectangle())
            .onLongPressGesture(minimumDuration: 0, maximumDistance: 1000, perform: {}, onPressingChanged: { pressing in
                model.comparingOriginal = pressing
            })
            .help("按住查看调色前的原图")
    }
}

struct PlayerLayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> PlayerNSView {
        let view = PlayerNSView()
        view.playerLayer.player = player
        return view
    }

    func updateNSView(_ view: PlayerNSView, context: Context) {
        if view.playerLayer.player !== player { view.playerLayer.player = player }
    }
}

final class PlayerNSView: NSView {
    let playerLayer = AVPlayerLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer = CALayer()
        layer?.backgroundColor = NSColor.black.cgColor
        playerLayer.videoGravity = .resizeAspect
        layer?.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }
}
