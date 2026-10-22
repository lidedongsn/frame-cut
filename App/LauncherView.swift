import FCCore
import SwiftUI

/// 启动页：新建 / 打开 / 最近项目。
struct LauncherView: View {
    @Environment(AppModel.self) private var app
    @State private var confirmClear = false

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("FrameCut")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.text)
                    Text("免费、本地、无水印的 vlog 剪辑")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.secondary)
                }
                Button {
                    app.newProject()
                } label: {
                    Label("开始创作", systemImage: "plus")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 220, height: 52)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.black)
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.accent))

                Button("打开工程…") { app.openPanel() }
                    .buttonStyle(PanelButtonStyle())
                Spacer()
            }
            .padding(48)
            .padding(.top, 40)
            .frame(width: 380, alignment: .leading)

            Divider().overlay(Theme.border)

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("最近项目")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.secondary)
                    Spacer()
                    if !app.recent.isEmpty {
                        Button("清空") { confirmClear = true }
                            .buttonStyle(.plain)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.tertiary)
                            .help("清空最近项目记录，不会删除工程文件")
                    }
                }
                if app.recent.isEmpty {
                    Spacer()
                    Text("还没有项目，点击「开始创作」新建一个")
                        .foregroundStyle(Theme.tertiary)
                        .frame(maxWidth: .infinity)
                    Spacer()
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 16)], spacing: 16) {
                            ForEach(app.recent, id: \.self) { url in
                                RecentCard(url: url) { app.open(url: url) }
                                    .contextMenu {
                                        Button("打开") { app.open(url: url) }
                                        Button("在访达中显示") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                                        Divider()
                                        Button("从最近项目中移除") { app.removeRecent(url) }
                                    }
                            }
                        }
                    }
                }
            }
            .padding(40)
            .padding(.top, 40)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .confirmationDialog("清空最近项目？", isPresented: $confirmClear) {
            Button("清空", role: .destructive) { app.clearRecent() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("只清除列表记录，工程文件不会被删除。")
        }
    }
}

private struct RecentCard: View {
    let url: URL
    let action: () -> Void
    @State private var hovering = false

    private var modified: String {
        let date = (try? url.appendingPathComponent("project.json").resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        guard let date else { return "" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Theme.raised)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .overlay(Image(systemName: "film").font(.system(size: 28)).foregroundStyle(Theme.tertiary))
                Text(url.deletingPathExtension().lastPathComponent)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Text(modified).font(.system(size: 11)).foregroundStyle(Theme.tertiary)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(hovering ? Theme.hover : Theme.panel))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(url.path)
    }
}
