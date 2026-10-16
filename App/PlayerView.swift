import AVFoundation
import FCCore
import SwiftUI

/// 预览区：画面 + 播放控制。
struct PlayerPanel: View {
    @Bindable var model: EditorModel

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
                    .frame(width: 80, alignment: .trailing)
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
                    .frame(width: 80, alignment: .leading)
            }
            .foregroundStyle(Theme.text)
            .frame(height: 40)
            .disabled(model.duration == .zero)
        }
        .background(Theme.window)
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
