# FrameCut MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 实现设计文档中的 FrameCut MVP：一个可完成“新建工程 → 导入 → 剪辑 → 裁剪滤镜 → 转场 → 音频 → 字幕 → 自动保存 → 导出”闭环的 macOS vlog 剪辑应用。

**Architecture:** 本地 Swift Package `FrameCutKit`（FCCore / FCMedia / FCEngine / FCTranscribe）＋ XcodeGen 生成的 SwiftUI App。FCCore 为纯值类型模型与编辑逻辑；FCEngine 把工程编译为 AVComposition ＋ 自定义合成器，预览与导出共用。

**Tech Stack:** Swift 6 编译器（Swift 5 语言模式）、SwiftUI、AVFoundation、Core Image（Metal 后端）、Core Text、WhisperKit 1.1.x、XcodeGen、XCTest、ffmpeg（仅生成测试素材）。

**Spec:** `docs/superpowers/specs/2026-10-16-framecut-mvp-design.md`

## Global Constraints

- macOS 14.0 最低版本；arm64。
- 时间统一用 `Time`（整数微秒，`Int64`），与 `CMTime(value:, timescale: 1_000_000)` 互转。（实现者决定：替代设计文档中的“有理数”，同样无浮点累积误差）
- 渲染用 Core Image（`CIContext(mtlDevice:)`，Metal 后端）实现合成、滤镜、转场；不写独立 .metal 文件。（实现者决定：替代手写 Metal shader，降低风险，性能同为 GPU）
- 时间线 UI 用 SwiftUI 视图逐片段绘制（片段数 < 200，性能足够）。（实现者决定）
- 界面文字全部中文。
- 唯一第三方依赖：WhisperKit（`from: "1.1.0"`）。
- 变速范围 0.25–4.0；转场时长 0.2–2.0 秒；图片默认 3 秒；片段最短 0.1 秒；撤销上限 100 步；自动保存防抖 2 秒。
- 工程包扩展名 `.framecut`，内含 `project.json`，`schemaVersion = 1`。

## Review Focus

1. 转场两侧片段很短（< 转场时长两倍）——转场时长应被自动夹到两段各自时长一半以内，播放不出错。
2. 素材文件被移动 / 删除后打开工程——应提示丢失并允许重新定位，而不是崩溃或黑屏无提示。
3. 竖拍手机视频（带旋转元数据）——预览与导出方向正确。
4. 主轨为空时播放 / 导出 / 识别字幕——按钮禁用或给出提示，不崩溃。
5. 导出过程中取消或关闭窗口——临时文件被删除，应用状态恢复。

对应测试分别放在 Task 3（1）、Task 5（2）、Task 7（3、4）、Task 8（5）。

---

## File Structure

```
project.yml                                   XcodeGen 配置
scripts/make-test-media.sh                    用 ffmpeg 生成测试素材到 TestMedia/
Packages/FrameCutKit/Package.swift
Packages/FrameCutKit/Sources/FCCore/
  Time.swift            Time 类型
  Models.swift          Project / MediaAsset / VideoClip / AudioClip / Transition / Subtitle / 样式与枚举
  TimelineLayout.swift  主轨布局纯函数
  ProjectEditing.swift  Project 上的编辑操作（mutating 扩展）
  EditorStore.swift     @Observable 编辑器状态 + 撤销重做 + 变更回调
  ProjectFile.swift     .framecut 读写、RecentProjects
Packages/FrameCutKit/Sources/FCMedia/
  MediaProbe.swift      探测素材 → MediaAsset
  ThumbnailProvider.swift  缩略图（actor，内存缓存）
  WaveformProvider.swift   波形峰值（actor）
Packages/FrameCutKit/Sources/FCEngine/
  RenderSize.swift      画幅 × 短边 → 像素尺寸
  CompositionBuilder.swift  Project → BuiltComposition
  RenderInstruction.swift   指令与图层描述
  FrameRenderer.swift   Core Image 合成：变换、滤镜、转场、字幕
  FilterLUT.swift       预设 → 3D LUT 数据
  SubtitleRenderer.swift   Core Text → CIImage（缓存）
  CompositorBridge.swift   AVVideoCompositing 实现，调用 FrameRenderer
  BlankVideo.swift      生成基底黑色视频
  Exporter.swift        AVAssetReader + AVAssetWriter 导出
  AudioExtractor.swift  主轨原声 → 16kHz 单声道 Float 数组
Packages/FrameCutKit/Sources/FCTranscribe/
  Transcriber.swift     协议 + WhisperKitTranscriber
Packages/FrameCutKit/Tests/FCCoreTests/…, FCEngineTests/…
App/
  FrameCutApp.swift     App 入口、菜单命令
  AppModel.swift        启动页 / 编辑器切换，打开与新建
  LauncherView.swift    最近项目 + 新建
  EditorModel.swift     @Observable：EditorStore、播放器、选中、播放头、自动保存
  EditorView.swift      三栏 + 时间线布局
  PlayerView.swift      AVPlayerLayer 包装 + 播放控制
  LibraryPanel.swift    素材 / 音乐 / 转场 / 滤镜 / 字幕 标签页
  InspectorPanel.swift  按选中对象显示属性
  TimelineView.swift    时间尺、轨道、片段、播放头、拖拽
  SubtitlePanel.swift   字幕列表、识别、样式
  ExportSheet.swift     导出设置与进度
  Theme.swift           颜色与尺寸
```

---

### Task 1: 工程脚手架与测试素材

**Files:** Create `project.yml`, `Packages/FrameCutKit/Package.swift`, 每个模块一个占位源文件, `App/FrameCutApp.swift`, `scripts/make-test-media.sh`

**Produces:** 模块名 `FCCore`, `FCMedia`, `FCEngine`, `FCTranscribe`；测试目标 `FCCoreTests`, `FCEngineTests`；`TestMedia/` 下 `landscape_10s.mp4`（1920×1080 30fps 带 440Hz 音频）、`portrait_rotated_6s.mov`（1920×1080 带 rotate=90 元数据）、`tone_20s.m4a`、`photo.jpg`。

- [ ] Step 1: 写 Package.swift（platforms `.macOS(.v14)`，swiftLanguageModes `[.v5]`，WhisperKit 依赖仅给 FCTranscribe）与 project.yml（App 目标依赖四个库，Info.plist 含 `NSMicrophoneUsageDescription` 不需要；`CFBundleDocumentTypes` 声明 `.framecut` 包）。
- [ ] Step 2: 运行 `xcodegen generate && xcodebuild -scheme FrameCut build`，期望 BUILD SUCCEEDED。
- [ ] Step 3: 运行 `scripts/make-test-media.sh`，期望四个文件生成。
- [ ] Step 4: Commit。

### Task 2: 核心模型与 Time

**Files:** `FCCore/Time.swift`, `FCCore/Models.swift`, Test `FCCoreTests/ModelTests.swift`

**Produces:**
- `struct Time: Codable, Hashable, Comparable, AdditiveArithmetic { var microseconds: Int64 }`；`init(seconds: Double)`，`seconds: Double`，`cmTime`，`init(_ cmTime:)`，`static func * (Time, Double) -> Time`，`/`。
- `enum AspectRatio: String, CaseIterable { r16x9, r9x16, r1x1, r4x3, r3x4 }`，`ratio: Double`，`displayName`。
- `enum MediaKind { video, image, audio }`；`struct MediaAsset { id: UUID, kind, name, path: String, bookmark: Data?, duration: Time, width: Int, height: Int, hasAudio: Bool, frameRate: Double }`，`url: URL`。
- `struct ClipTransform { scale = 1.0, offsetX = 0.0, offsetY = 0.0 /* 画布比例 */, quarterTurns = 0 }`
- `enum FilterPreset: String, CaseIterable { none, fresh, warm, film, mono, vintage, cool, vivid, fade, cinematic }`，`displayName`（原画、清新、暖阳、胶片、黑白、复古、冷调、鲜艳、褪色、电影）。
- `struct FilterSettings { preset = .none, intensity = 1.0, brightness = 0, contrast = 0, saturation = 0, temperature = 0 /* 均为 -1...1 */ }`，`isIdentity`。
- `struct VideoClip: Identifiable { id, assetID, sourceIn: Time, sourceOut: Time, speed = 1.0, volume = 1.0, muted = false, transform, filter }`，`sourceDuration`，`timelineDuration`（= 源时长 / speed）。
- `enum TransitionKind: String, CaseIterable { dissolve, fadeBlack, fadeWhite, pushLeft, pushRight, pushUp, pushDown, slideLeft, wipeLeft, zoom, blur }`，`displayName`。`struct Transition { kind, duration: Time }`。
- `struct AudioClip: Identifiable { id, assetID, start: Time, sourceIn, sourceOut, volume = 1.0, fadeIn = .zero, fadeOut = .zero }`，`duration`，`end`。
- `struct Subtitle: Identifiable { id, start, end, text }`。
- `struct RGBA { r, g, b, a: Double }`；`struct SubtitleStyle { fontName = "PingFangSC-Semibold", fontSize = 0.055 /* 画布高比例 */, textColor = 白, strokeColor = 黑, strokeWidth = 0.12 /* 字号比例 */, backgroundColor = 透明, verticalPosition = 0.85 /* 中心距顶部比例 */ }`。
- `struct Project { schemaVersion = 1, id, name, aspect = .r16x9, frameRate = 30, assets, mainTrack, transitions: [UUID: Transition] /* 键：后一片段 id */, musicTrack, subtitles, subtitleStyle }`，`asset(id:)`。

- [ ] Step 1: 测试 `testTimeArithmetic`（`Time(seconds: 1.5).microseconds == 1_500_000`；`Time(seconds: 2) / 2.0 == Time(seconds: 1)`）、`testClipTimelineDuration`（源 4s speed 2 → 2s）、`testProjectRoundTrip`（编码再解码相等）。
- [ ] Step 2: 跑 `swift test --package-path Packages/FrameCutKit --filter ModelTests`，期望 FAIL（未定义）。
- [ ] Step 3: 实现。
- [ ] Step 4: 期望 PASS。Commit。

### Task 3: TimelineLayout

**Files:** `FCCore/TimelineLayout.swift`, Test `FCCoreTests/TimelineLayoutTests.swift`

**Produces:** `struct ClipPlacement { clipID: UUID, index: Int, start: Time, duration: Time, lane: Int /* index % 2 */, transitionIn: Transition? /* 已夹紧 */ }`，`end`；`struct TimelineLayout { placements, duration; init(project:) ; func placement(for: UUID) -> ClipPlacement?; func clipIndex(at: Time) -> Int? /* 返回最后一个 start <= t 的片段 */ }`；`static func clampedTransitionDuration(_ d: Time, previous: Time, current: Time) -> Time`（= min(d, previous/2, current/2)）。

规则：`start[0] = 0`；`start[i] = end[i-1] - transitionIn[i].duration`；总时长 = 最后一段 end；空主轨 duration = 0。

- [ ] Step 1: 测试 `testSequentialNoTransitions`（3s + 2s → starts [0,3]，duration 5）、`testTransitionOverlap`（4s, 4s, 1s dissolve → starts [0,3]，duration 7）、`testTransitionClampedForShortClips`（1s 与 0.6s，转场 1s → 被夹到 0.3s）、`testSpeedAffectsDuration`、`testEmpty`。
- [ ] Step 2–4: 失败 → 实现 → 通过。Commit。

### Task 4: 编辑操作与 EditorStore

**Files:** `FCCore/ProjectEditing.swift`, `FCCore/EditorStore.swift`, Tests `ProjectEditingTests.swift`, `EditorStoreTests.swift`

**Produces（`extension Project`，均 mutating）：**
- `appendToMain(assetID:) -> UUID?`、`insertIntoMain(assetID:, at index: Int) -> UUID?`（视频取全长；图片 3s；音频不允许）
- `splitMain(at: Time) -> UUID?`（返回新片段 id；距片段边界 < 0.1s 时返回 nil）
- `removeMain(id:)`（同时删其转场）、`moveMain(id:, to: Int)`
- `trimMain(id:, sourceIn:, sourceOut:)`（夹到 [0, 资产时长]，图片无上限，最短 0.1s）
- `setSpeed(id:, _:)`（夹到 0.25...4）、`updateMain(id:, _ body: (inout VideoClip) -> Void)`
- `setTransition(_:, before clipID:)`、`applyTransitionToAll(_: Transition?)`（第 0 段不带转场）
- `applyFilterToAll(_: FilterSettings)`
- `addMusic(assetID:, at: Time) -> UUID?`、`splitMusic(id:, at:)`、`removeMusic(id:)`、`updateMusic(id:, _:)`
- `addSubtitle(at: Time, text: String, duration: Time = 2s) -> UUID`、`updateSubtitle(id:, _:)`、`removeSubtitle(id:)`、`replaceSubtitles(_: [Subtitle])`（按 start 排序）
- `func missingAssets(fileExists: (String) -> Bool) -> [MediaAsset]`

**EditorStore（`@Observable @MainActor final class`）：** `init(project:)`，`private(set) var project`，`func perform(_ body: (inout Project) -> Void)`，`beginCoalescing()` / `endCoalescing()`（期间的多次 perform 只记一次撤销），`undo()`，`redo()`，`canUndo`，`canRedo`，`var onChange: ((Project) -> Void)?`，撤销上限 100。

- [ ] Step 1: 测试 `testSplitInMiddle`（10s 片段在 4s 处分割 → 两段源区间 [0,4]、[4,10]）、`testSplitRespectsSpeed`（speed 2，时间线 2s 处 → 源 4s）、`testSplitNearEdgeRejected`、`testRemoveDropsTransition`、`testMove`、`testTrimClamps`、`testApplyTransitionToAllSkipsFirst`、`testUndoRedo`、`testCoalescing`（begin、3 次 perform、end → 一次 undo 回到最初）、`testUndoLimit`。
- [ ] Step 2–4: 失败 → 实现 → 通过。Commit。

### Task 5: 工程读写与最近项目

**Files:** `FCCore/ProjectFile.swift`, Test `ProjectFileTests.swift`

**Produces:** `enum ProjectFile { static let fileExtension = "framecut"; static func write(_: Project, to packageURL: URL) throws /* 原子写 project.json */; static func read(from: URL) throws -> Project; static func cacheDirectory(for: URL) -> URL }`；`struct RecentProjects { static func list() -> [URL]; static func add(_ url: URL); static func remove(_ url: URL) }`（UserDefaults，最多 20，存在性过滤）。

- [ ] Step 1: 测试 `testWriteRead`、`testMissingAssetsDetected`（路径不存在的资产被 `missingAssets` 返回）。
- [ ] Step 2–4。Commit。

### Task 6: FCMedia 探测、缩略图、波形

**Files:** `FCMedia/*.swift`, Test `FCEngineTests/MediaProbeTests.swift`（与引擎共用测试素材）

**Produces:** `enum MediaProbe { static func probe(url: URL) async throws -> MediaAsset }`（视频尺寸应用 preferredTransform 后的显示尺寸；音频 width/height = 0；图片 duration = 0 表示无限）；`actor ThumbnailProvider { static let shared; func thumbnail(url: URL, time: Time, maxHeight: CGFloat) async -> CGImage? }`；`actor WaveformProvider { static let shared; func peaks(url: URL, perSecond: Int = 50) async -> [Float] }`。

- [ ] Step 1: 测试 `testProbeLandscape`（1920×1080，约 10s，hasAudio）、`testProbeRotated`（显示尺寸 1080×1920）、`testProbeImage`、`testWaveformNonEmpty`。
- [ ] Step 2–4。Commit。

### Task 7: 合成构建与渲染

**Files:** `FCEngine/RenderSize.swift`, `BlankVideo.swift`, `RenderInstruction.swift`, `FilterLUT.swift`, `SubtitleRenderer.swift`, `FrameRenderer.swift`, `CompositorBridge.swift`, `CompositionBuilder.swift`, Test `FCEngineTests/CompositionTests.swift`

**Produces:**
- `enum RenderSize { static func size(aspect: AspectRatio, shortSide: Int) -> CGSize }`（偶数像素；16:9 + 1080 → 1920×1080）。
- `struct BuiltComposition { composition: AVComposition, videoComposition: AVVideoComposition, audioMix: AVAudioMix, duration: Time }`。
- `enum CompositionBuilder { static func build(project: Project, renderSize: CGSize, includeMusic: Bool = true) async throws -> BuiltComposition; static func makeVideoComposition(project:, renderSize:, structure:) -> AVVideoComposition }`。
- 主视频 A/B 轨按 `ClipPlacement.lane`；音频 A/B 同理；音乐每段一条轨；基底轨为 `BlankVideo.url()` 拉伸至总时长；转场重叠处音量交叉渐变。
- `final class RenderInstruction: NSObject, AVVideoCompositionInstructionProtocol`：`layers: [LayerSpec]`、`transition: (Transition, CMTimeRange)?`、`scene: RenderScene`（字幕列表、样式、画布尺寸）。
- `struct LayerSpec { source: .track(CMPersistentTrackID) | .image(URL), naturalSize, preferredTransform, transform: ClipTransform, filter: FilterSettings }`。
- `final class FrameRenderer { static let shared; func render(request: AVAsynchronousVideoCompositionRequest) }`：fill 画幅 → 用户变换 → 滤镜（CIColorControls + CITemperatureAndTint + CIColorCubeWithColorSpace，强度烘焙入 LUT）→ 转场 → 字幕叠加。
- 转场实现：dissolve=CIDissolveTransition；fadeBlack/White=两段分别与纯色混合；push=两层同向平移；slide=后段平移覆盖；wipe=按进度矩形遮罩（CIBlendWithMask）；zoom=前段放大淡出；blur=两段高斯模糊 + 溶解（模糊半径 sin 曲线峰值 30px@1080）。

- [ ] Step 1: 测试 `testBuildDurations`（两段 10s 视频 + 1s 转场 → composition 时长 19s ±1 帧）、`testRenderFrameNotBlank`（用 `AVAssetImageGenerator` 带 videoComposition 取 5s 处帧，像素非全黑）、`testImageClipRenders`、`testRotatedVideoPortraitOutput`（9:16 工程中旋转视频取帧，图像主体不旋转——取中心像素与原素材颜色一致）、`testEmptyProjectBuildThrowsOrEmpty`（主轨为空时 build 抛 `CompositionError.empty`）。
- [ ] Step 2–4。Commit。

### Task 8: 导出与原声提取

**Files:** `FCEngine/Exporter.swift`, `FCEngine/AudioExtractor.swift`, Test `ExporterTests.swift`

**Produces:** `struct ExportSettings { shortSide: Int (720/1080/2160), frameRate: Int, codec: .h264 | .hevc }`，`bitrate`（按像素数 × 帧率估算）；`final class Exporter { func export(project:, settings:, to: URL, progress: @escaping @Sendable (Double) -> Void) async throws }`（支持 Task 取消，取消时删除输出文件，抛 `CancellationError`）；`enum AudioExtractor { static func mainTrackSamples(project:) async throws -> [Float] /* 16kHz 单声道 */ }`。

- [ ] Step 1: 测试 `testExport720p`（导出文件可读，尺寸 1280×720，时长匹配）、`testExportCancelRemovesFile`、`testAudioExtractorLength`（10s → 约 160000 样本）。
- [ ] Step 2–4。Commit。

### Task 9: 字幕识别

**Files:** `FCTranscribe/Transcriber.swift`

**Produces:** `struct TranscriptSegment { start: Time, end: Time, text: String }`；`protocol Transcriber { func transcribe(samples: [Float], progress: @escaping @Sendable (TranscribeProgress) -> Void) async throws -> [TranscriptSegment] }`；`enum TranscribeProgress { downloading(Double), transcribing(Double) }`；`final class WhisperKitTranscriber: Transcriber`（模型 `openai_whisper-small`，下载到 `~/Library/Application Support/FrameCut/Models`，语言自动检测，繁体转简体）。

- [ ] Step 1: 编译通过；手动验收中实际识别一次（模型下载依赖网络，不放入自动测试）。Commit。

### Task 10: App 外壳、启动页、编辑器状态

**Files:** `App/FrameCutApp.swift`, `AppModel.swift`, `LauncherView.swift`, `EditorModel.swift`, `Theme.swift`

**Produces:** `@Observable final class AppModel { var editor: EditorModel?; func newProject(); func open(url:); func closeProject() }`；`@Observable @MainActor final class EditorModel { store: EditorStore, packageURL, player: AVPlayer, playhead: Time, isPlaying, selection: Selection?, zoom: Double /* 点/秒 */; func importFiles([URL]) async; func togglePlay(); func seek(to:); func rebuildPlayback() /* 防抖 150ms；结构未变只替换 videoComposition/audioMix */; func scheduleAutosave() }`；`enum Selection { video(UUID), music(UUID), subtitle(UUID), transition(UUID) }`。菜单命令：新建 ⌘N、打开 ⌘O、保存 ⌘S、撤销 ⌘Z、重做 ⇧⌘Z、分割 ⌘B、删除 ⌫、播放 空格、导出 ⌘E。

- [ ] Step 1: 构建并启动 App，启动页出现、可新建工程（保存对话框创建 .framecut）。Commit。

### Task 11: 编辑器界面（预览、素材库、检查器、时间线）

**Files:** `App/EditorView.swift`, `PlayerView.swift`, `LibraryPanel.swift`, `InspectorPanel.swift`, `TimelineView.swift`

- 时间线：时间尺（点击 / 拖动定位）、主轨片段（缩略图条、选中高亮、两端修剪手柄、拖动排序）、交界处转场标记（点击选中）、音乐轨（波形、拖动位置、修剪）、字幕轨（拖动、修剪）、播放头；⌘滚轮 / 捏合缩放。
- 素材库标签：素材（导入按钮、拖入、双击或拖到时间线添加）、音乐（导入音频）、转场（网格，点击应用到选中交界或“应用到全部”）、滤镜（网格预览名称，应用到选中片段或全部）、字幕。
- 检查器：视频片段（缩放、位移、旋转、速度、音量、静音、滤镜强度与调节）、音乐（音量、淡入淡出）、转场（类型、时长）、字幕（文字、时间）、无选中时为工程设置（画幅、帧率）。
- 丢失素材：打开时弹窗列出，可逐个重新定位。

- [ ] Step 1: 用测试素材手动走完：导入 → 分割 → 排序 → 修剪 → 变速 → 撤销，预览随之更新。Commit。

### Task 12: 字幕面板与导出面板

**Files:** `App/SubtitlePanel.swift`, `App/ExportSheet.swift`

- 字幕面板：识别按钮（进度：下载 / 识别），列表逐条编辑文字与时间，样式区（字体、字号、颜色、描边、背景、位置）。
- 导出：分辨率、帧率、编码、保存位置；进度条、取消；完成后“在 Finder 中显示”。

- [ ] Step 1: 手动导出一条带转场、滤镜、音乐、字幕的 1080p 视频，用 ffprobe 验证尺寸和时长。Commit。

### Task 13: 端到端验收

- [ ] Step 1: `swift test` 全部通过；`xcodebuild build` 成功。
- [ ] Step 2: 按设计文档“目标”逐条手动验收并记录问题，修复后 Commit。

---

## HDR 追加任务（对应设计文档第 8 节）

### Task 14: 模型与素材识别
- `enum HDRFormat { hlg, pq, dolbyVision }`，`MediaAsset.hdr: HDRFormat?`；`enum ColorMode { sdr, hdr }`，`Project.colorMode`、`Project.colorModeIsAutomatic`；自定义解码兼容旧文件。
- `Project.addAssets(_:)`：追加素材并在自动模式下遇到 HDR 素材切到 `.hdr`。
- `MediaProbe` 读取格式描述的传输函数与杜比视界配置。
- 测试：`testLegacyJSONDecodesWithDefaults`、`testImportHDRSwitchesColorMode`、`testManualColorModeNotOverridden`、`testProbeHLG`、`testProbePQ`、`testProbeSDRHasNoHDR`。

### Task 15: 色调映射与 HDR 调色
- `ToneMap.map(_ x: Double) -> Double`（相对参考白的线性亮度；knee 0.7，峰值 1000/203 → 1.0）与 65³ PQ 空间 LUT。
- `FilterLUT` 合并调节参数，按 `GradingSpace { sdr, hlg }` 生成 LUT。
- 测试：`testBelowKneeIdentity`、`testReferenceWhite`、`testMonotonic`、`testPeakMapsToOne`、`testHighlightsDistinct`。

### Task 16: HDR 渲染与导出
- `DynamicRangeOutput { sdr, hlg, pq }`；三种合成器子类；`makeVideoComposition(project:renderSize:output:)`；FrameRenderer 浮点工作空间与按输出渲染。
- `ExportSettings.dynamicRange`；HDR 时 HEVC Main10、x420、BT.2020 + HLG/PQ 标记。
- 测试：HLG 源在 HLG 输出时峰值线性值 > 4；SDR 输出时色带严格递增且峰值不截成参考白；HDR 工程字幕不超过 1.05；HLG / PQ / SDR 导出的传输函数与位深正确，HLG 导出峰值码值约 940。

### Task 17: 界面
- 工程设置色彩模式、素材与片段 HDR 标记、导出面板动态范围选项、预览按工程模式输出。
