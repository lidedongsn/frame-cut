<p align="center">
  <img src="docs/images/social-preview.png" alt="FrameCut：为 Apple 芯片 Mac 打造的 vlog 剪辑软件">
</p>

<p align="center">
  <a href="https://github.com/lidedongsn/frame-cut/releases/latest"><img src="https://img.shields.io/github/v/release/lidedongsn/frame-cut?label=release&color=29d1db" alt="release"></a>
  <a href="https://github.com/lidedongsn/frame-cut/releases"><img src="https://img.shields.io/github/downloads/lidedongsn/frame-cut/total?color=29d1db" alt="downloads"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-black?logo=apple" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Apple%20silicon-M1%20%E5%8F%8A%E6%9B%B4%E6%96%B0-black" alt="Apple silicon">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT"></a>
</p>

<p align="center"><b>为 Apple 芯片 Mac 打造的 vlog 剪辑软件</b> · 免费 · 无水印 · 全部本地运行 · 安装包不到 3 MB<br>
<a href="https://github.com/lidedongsn/frame-cut/releases/latest"><b>⬇ 下载最新版</b></a></p>

<p align="center">中文 · <a href="README.en.md">English</a></p>

---

拍完一段旅行、一顿饭、一个周末，想剪成 3 分钟的 vlog：分割、调色、加转场、配音乐、上字幕，然后导出发布。
FrameCut 只做这件事，并把它做到又快又顺手。所有功能免费，导出不加水印，也不需要登录账号。

## 为什么是 FrameCut

### 只为 Apple 芯片而生

FrameCut 只支持 Apple 芯片（M1 及更新的 M 系列芯片），不为兼容 Intel 背包袱。
芯片里每一块专用硬件都被派上了用场，繁重的工作几乎不占用 CPU：

| 工作 | 交给谁 | 带来什么 |
|---|---|---|
| 视频解码、编码 | **媒体引擎**（硬件编解码器） | 导出飞快，风扇安静，笔记本不烫 |
| 调色、转场、字幕合成 | **GPU**（Metal + Core Image，16 位浮点） | 拖动滑块即时生效，HDR 高光不截断 |
| 语音转字幕 | **神经网络引擎** + GPU | 离线识别，免费且不上传任何声音 |
| 素材与预览 | **统一内存** | 解码帧直接交给 GPU，不来回拷贝 |

### 快，而且有数据

在一台 **M2 Mac（16 GB）** 上实测，工程为约 3 分钟（170 秒）的 vlog，包含 20 个片段、转场、滤镜、背景音乐和 40 条字幕：

| 场景 | 用时 | 速度 |
|---|---|---|
| 导出 1080p | 约 26 秒 | 6.6 倍速 |
| 导出 1080p HDR（iPhone 拍摄的 HLG → HLG） | 约 28 秒 | 6.0 倍速 |
| 导出 4K | 约 95 秒 | 1.8 倍速 |
| 调色时重算整套颜色（含 HSL 分色） | 不到 1 毫秒 | 拖动无卡顿 |

导出速度已经达到 M2 硬件编码器的上限：实测同时开 1 路、2 路、3 路编码，总吞吐完全一样。
预览分辨率会跟随窗口大小自动调整，渲染跟不上时会自动降一档，保证播放流畅。

### 小，而且干净

- **安装包不到 3 MB，安装后不到 10 MB。** 不内置浏览器内核，不捆绑插件，全部使用系统原生框架。
- 语音识别模型约 600 MB，**第一次识别字幕时才下载**；不用这个功能就不占空间，用完也可以在字幕页一键删除。
- 内存缓存都有上限，关闭工程或系统内存紧张时会自动释放；语音模型空闲 3 分钟后自动卸载。
- 工程文件只记录素材的位置，不复制视频，不会悄悄占满硬盘。

### 本地优先，尊重隐私

剪辑、调色、导出、语音识别全部在本机完成。FrameCut 唯一会联网的时候，是首次下载语音识别模型
（官方源不通时自动改用国内镜像）。素材、工程、声音都不会离开你的 Mac。

### 原生的 HDR 支持

iPhone 拍的视频大多是 HDR（杜比视界 / HLG）。FrameCut 能自动识别，并整条链路按 HDR 处理：

- 10 位解码，浮点合成，高光细节不会被截断
- 在支持 EDR 的屏幕（如 MacBook Pro 的 XDR 屏）上预览真实亮度
- 可导出 HDR（HLG，各大平台通用）、HDR10，或自动色调映射成普通 SDR
- HDR 和普通素材、照片、字幕放在一起剪，亮度保持一致

## 功能

| | |
|---|---|
| **剪辑** | 分割（⌘B）、拖动排序和修剪、变速 0.25x–4x（不变调）、无限撤销 |
| **画面** | 5 种画幅，缩放、位移、旋转；自动匹配素材的比例和帧率 |
| **调色** | 10 款滤镜和 .cube LUT，基础调节，HSL 8 色，锐化、暗角；复制粘贴调色，按住对比原图，存为预设 |
| **转场** | 11 种，可一键应用到全部片段 |
| **音频** | 多轨配乐、旁白、音效，边看画面边录旁白，分离视频原声；有人说话时背景音乐自动调低，可手动调整 |
| **文字** | 8 款标题预设，4 种动画，在预览里直接拖动 |
| **字幕** | 本地 Whisper 识别生成，剪辑后自动跟随画面，导入导出 SRT |
| **导出** | 720p–4K，24–60 fps，H.264 / HEVC 硬件编码，无水印 |
| **工程** | 自动保存；素材被移动后可重新定位 |

## 安装

1. 下载 `FrameCut-<版本>.dmg`，双击打开，把 FrameCut 拖进「应用程序」。
2. 第一次打开时，系统会提示“Apple 无法验证 FrameCut 是否包含恶意软件”，点「完成」。
3. 打开「系统设置 → 隐私与安全性」，在“安全性”一栏找到 FrameCut，点「仍要打开」并输入密码。只需要做这一次。

> FrameCut 目前没有向 Apple 付费注册开发者签名，所以第一次打开需要手动放行。

**系统要求**：macOS 14 或更新版本，Apple 芯片（M1 及更新的 M 系列芯片）。

## 喜欢的话

如果 FrameCut 帮你省了时间，欢迎点个 ⭐ Star，让更多人看到它。
遇到问题或有想要的功能，请在 [Issues](https://github.com/lidedongsn/frame-cut/issues) 里告诉我。

## 开发

需要 macOS 14+、Xcode 16+、Homebrew。

```bash
make setup         # 安装 XcodeGen、ffmpeg 并生成 FrameCut.xcodeproj
make run-release   # 构建并打开发布版（日常使用推荐）
make test          # 单元测试（首次会用 ffmpeg 生成测试素材到 TestMedia/）
make check         # 提交前检查：测试 + 构建
make dmg           # 打包安装包 build/FrameCut-<版本>.dmg，可直接发给别人
make strings       # 改了界面文字后，把新文案同步进翻译文件（*.xcstrings）
make help          # 全部命令
```

可选实测（默认跳过）：

```bash
make bench                                                                                       # 导出、分阶段、编码器性能
FC_TRANSCRIBE=1 swift test --package-path Packages/FrameCutKit --filter testRealTranscription   # 真实语音识别（会下载约 600MB 模型）
```

日志：打开“控制台”App，按子系统 `com.lidedongsn.framecut` 过滤（分类 project / media / export / transcribe / cache）。

## 数据存放位置

| 位置 | 内容 | 清理 |
|---|---|---|
| 工程文件 `*.framecut` | 工程数据和录的旁白（素材只引用，不复制） | 删除工程即删除 |
| `~/Library/Application Support/FrameCut/Models` | 语音识别模型，约 600MB | 字幕页「删除」 |
| `~/Library/Application Support/FrameCut/LUTs` | 导入的 LUT | 滤镜页右键删除 |
| `~/Library/Application Support/FrameCut/GradePresets.json` | 调色预设 | 滤镜页右键删除 |
| `~/Library/Caches/FrameCut` | 几 KB 的内部文件 | 自动维护 |

## 结构

| 模块 | 职责 |
|---|---|
| `Packages/FrameCutKit/Sources/FCCore` | 工程数据模型、时间线布局、编辑操作、撤销重做、工程读写 |
| `Packages/FrameCutKit/Sources/FCMedia` | 素材探测、缩略图、波形 |
| `Packages/FrameCutKit/Sources/FCEngine` | 合成构建、Core Image（Metal）渲染：滤镜 / 转场 / 字幕，导出 |
| `Packages/FrameCutKit/Sources/FCTranscribe` | WhisperKit 本地字幕识别（官方源不可达时自动使用 hf-mirror 镜像） |
| `App` | SwiftUI 界面 |

## 许可证

[MIT](LICENSE)。语音识别基于 [WhisperKit](https://github.com/argmaxinc/WhisperKit)（MIT）与 OpenAI Whisper 模型。
