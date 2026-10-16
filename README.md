# FrameCut

免费、本地运行、导出无水印的 macOS vlog 剪辑工具（对标剪映核心剪辑体验）。

## 功能（MVP）

- 工程：新建 / 打开 / 最近项目，编辑后 2 秒自动保存
- 导入：视频、照片、音乐，支持拖入窗口；素材丢失可重新定位
- 剪辑：分割（⌘B）、删除（⌫）、拖动排序、拖动两端修剪、变速 0.25x–4x（变速不变调）、撤销重做
- 画面：画幅 16:9 / 9:16 / 1:1 / 4:3 / 3:4，缩放、位移、旋转
- 滤镜：10 个风格预设 + 强度，亮度 / 对比度 / 饱和度 / 色温，可一键应用到全部
- 转场：叠化、闪黑、闪白、四向推移、滑入、擦除、放大、模糊，可一键应用到全部
- 音频：原声音量 / 静音，背景音乐（位置、裁剪、分割、音量、淡入淡出）
- 字幕：本地语音识别自动生成（WhisperKit，离线、免费），逐条校对，全局样式
- 导出：720p / 1080p / 4K，24–60fps，H.264 / HEVC 硬件编码，无水印
- HDR：识别 HLG / HDR10 / 杜比视界（如 iPhone 拍摄），导入后自动切换为 HDR 工程；10 位处理链路、浮点合成，高光不截断；
  HDR 预览（支持 EDR 的屏幕显示真实亮度）；导出 HDR（HLG）、HDR10（PQ，含静态元数据）或 SDR（自动色调映射）；
  HDR 与 SDR 素材、照片、字幕混剪时亮度一致

## 开发

需要 macOS 14+、Xcode 16+、[XcodeGen](https://github.com/yonaskolb/XcodeGen)。

```bash
xcodegen generate                    # 生成 FrameCut.xcodeproj
open FrameCut.xcodeproj              # 运行 FrameCut scheme

./scripts/make-test-media.sh         # 用 ffmpeg 生成测试素材到 TestMedia/
swift test --package-path Packages/FrameCutKit
```

可选实测（默认跳过）：

```bash
FC_TRANSCRIBE=1 swift test --package-path Packages/FrameCutKit --filter testRealTranscription  # 真实语音识别（会下载约 480MB 模型）
FC_BENCH=1 swift test --package-path Packages/FrameCutKit --filter Benchmark                    # 需先生成 TestMedia/vlog_180s.mp4
```

## 结构

| 模块 | 职责 |
|---|---|
| `Packages/FrameCutKit/Sources/FCCore` | 工程数据模型、时间线布局、编辑操作、撤销重做、工程读写 |
| `Packages/FrameCutKit/Sources/FCMedia` | 素材探测、缩略图、波形 |
| `Packages/FrameCutKit/Sources/FCEngine` | 合成构建、Core Image（Metal）渲染：滤镜 / 转场 / 字幕，导出 |
| `Packages/FrameCutKit/Sources/FCTranscribe` | WhisperKit 本地字幕识别（官方源不可达时自动使用 hf-mirror 镜像） |
| `App` | SwiftUI 界面 |

设计文档：`docs/superpowers/specs/2026-10-16-framecut-mvp-design.md`
