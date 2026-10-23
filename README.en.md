<p align="center">
  <img src="docs/images/social-preview.png" alt="FrameCut: a vlog editor built for Apple silicon Macs">
</p>

<p align="center">
  <a href="https://github.com/lidedongsn/frame-cut/releases/latest"><img src="https://img.shields.io/github/v/release/lidedongsn/frame-cut?label=release&color=29d1db" alt="release"></a>
  <a href="https://github.com/lidedongsn/frame-cut/releases"><img src="https://img.shields.io/github/downloads/lidedongsn/frame-cut/total?color=29d1db" alt="downloads"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-black?logo=apple" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Apple%20silicon-M1%20or%20later-black" alt="Apple silicon">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT"></a>
</p>

<p align="center"><b>A vlog editor built for Apple silicon Macs</b> · Free · No watermark · Fully on-device · Under 3 MB download<br>
<a href="https://github.com/lidedongsn/frame-cut/releases/latest"><b>⬇ Download the latest release</b></a></p>

<p align="center"><a href="README.md">中文</a> · English</p>

---

You shot a trip, a dinner, a weekend, and you want a three-minute vlog out of it: trim, color, add transitions,
music and captions, then export and post. FrameCut does exactly that, and does it fast.
Every feature is free, exports carry no watermark, and there is no account to sign in to.

## Why FrameCut

### Built only for Apple silicon

FrameCut runs on Apple silicon (M1 or later) only, with no Intel compatibility baggage.
Every dedicated block on the chip is put to work, so the heavy lifting barely touches the CPU:

| Work | Runs on | What you get |
|---|---|---|
| Video decode and encode | **Media engine** (hardware codecs) | Fast exports, quiet fans, a cool laptop |
| Color, transitions, captions | **GPU** (Metal + Core Image, 16-bit float) | Sliders apply instantly; HDR highlights are never clipped |
| Speech-to-caption | **Neural Engine** + GPU | Offline, free, and no audio ever leaves your Mac |
| Media and preview | **Unified memory** | Decoded frames go straight to the GPU, with no copies back and forth |

### Fast, with numbers to show it

Measured on an **M2 Mac (16 GB)** with a roughly three-minute (170 s) vlog of 20 clips, transitions, filters,
background music and 40 captions:

| Task | Time | Speed |
|---|---|---|
| Export 1080p | about 26 s | 6.6× realtime |
| Export 1080p HDR (iPhone HLG → HLG) | about 28 s | 6.0× realtime |
| Export 4K | about 95 s | 1.8× realtime |
| Recompute the full color grade (including HSL) | under 1 ms | No lag while dragging |

Export speed is already at the limit of the M2's hardware encoder: one, two or three parallel encode sessions
deliver exactly the same total throughput. Preview resolution follows the window size and steps down
automatically if rendering falls behind, so playback stays smooth.

### Small and tidy

- **Under 3 MB to download, under 10 MB installed.** No embedded browser engine, no bundled plug-ins, only native system frameworks.
- The speech model (about 600 MB) is **downloaded the first time you generate captions**. If you never use
  captions it takes no space, and you can delete it from the Captions panel with one click.
- Every in-memory cache has a limit and is released when you close a project or the system runs low on memory;
  the speech model unloads itself after three idle minutes.
- Project files only reference your media. Videos are never copied, so your disk won't quietly fill up.

### Local first, private by design

Editing, color, export and speech recognition all happen on your Mac. The only time FrameCut goes online is to
download the speech model the first time (falling back to a mirror if the official host is unreachable).
Your media, projects and voice never leave the machine.

### Native HDR

Most iPhone footage is HDR (Dolby Vision / HLG). FrameCut detects it and keeps the whole pipeline in HDR:

- 10-bit decode and floating-point compositing, so highlight detail is never clipped
- True-brightness preview on EDR displays (such as the XDR display on MacBook Pro)
- Export as HDR (HLG, accepted by all major platforms), HDR10, or tone-mapped SDR
- Mix HDR clips with SDR clips, photos and captions at consistent brightness

## Features

| | |
|---|---|
| **Edit** | Split (⌘B), drag to reorder and trim, speed 0.25×–4× (pitch preserved), unlimited undo |
| **Frame** | 5 aspect ratios, scale, position, rotation; matches your footage's aspect ratio and frame rate |
| **Color** | 10 looks and .cube LUTs, basic adjustments, 8-range HSL, sharpen, vignette; copy/paste grades, hold to compare, save presets |
| **Transitions** | 11 kinds, apply to all clips in one click |
| **Audio** | Multitrack music, voiceover and sound effects; record voiceover over the picture; detach a clip's audio; music ducks automatically under speech, adjustable by hand |
| **Text** | 8 title presets, 4 animations, drag directly on the preview |
| **Captions** | Generated on-device with Whisper, follow your edits, SRT import/export |
| **Export** | 720p–4K, 24–60 fps, H.264 / HEVC hardware encoding, no watermark |
| **Projects** | Autosave; relink media that has been moved |

> The interface is currently in Chinese.

## Install

1. Download `FrameCut-<version>.dmg`, open it, and drag FrameCut into **Applications**.
2. The first time you open it, macOS says it "cannot verify that FrameCut is free of malware". Click **Done**.
3. Open **System Settings → Privacy & Security**, find FrameCut under "Security", click **Open Anyway** and
   enter your password. You only need to do this once.

> FrameCut is not yet signed with a paid Apple Developer ID, which is why macOS asks you to approve it the first time.

**Requirements**: macOS 14 or later, Apple silicon (M1 or later).

## Like it?

If FrameCut saves you time, please give it a ⭐ star so more people can find it.
Bugs and feature requests are welcome in [Issues](https://github.com/lidedongsn/frame-cut/issues).

## Development

Requires macOS 14+, Xcode 16+ and Homebrew.

```bash
make setup         # install XcodeGen and ffmpeg, generate FrameCut.xcodeproj
make run-release   # build and open the Release app (recommended for daily use)
make test          # unit tests (generates test media into TestMedia/ with ffmpeg on first run)
make check         # pre-commit check: tests + build
make dmg           # package build/FrameCut-<version>.dmg, ready to share
make help          # list all commands
```

Optional measurements (skipped by default):

```bash
make bench                                                                                       # export, per-stage and encoder benchmarks
FC_TRANSCRIBE=1 swift test --package-path Packages/FrameCutKit --filter testRealTranscription   # real speech recognition (downloads ~600 MB model)
```

Logs: open the Console app and filter by subsystem `com.lidedongsn.framecut`
(categories: project / media / export / transcribe / cache).

## Where data lives

| Location | Contents | How to remove |
|---|---|---|
| Project files `*.framecut` | Project data and recorded voiceovers (media is referenced, never copied) | Delete the project |
| `~/Library/Application Support/FrameCut/Models` | Speech model, about 600 MB | **Delete** in the Captions panel |
| `~/Library/Application Support/FrameCut/LUTs` | Imported LUTs | Right-click in the Filters panel |
| `~/Library/Application Support/FrameCut/GradePresets.json` | Color presets | Right-click in the Filters panel |
| `~/Library/Caches/FrameCut` | A few KB of internal files | Managed automatically |

## Architecture

| Module | Responsibility |
|---|---|
| `Packages/FrameCutKit/Sources/FCCore` | Project model, timeline layout, editing operations, undo/redo, project I/O |
| `Packages/FrameCutKit/Sources/FCMedia` | Media probing, thumbnails, waveforms |
| `Packages/FrameCutKit/Sources/FCEngine` | Composition, Core Image (Metal) rendering of color, transitions and captions, export |
| `Packages/FrameCutKit/Sources/FCTranscribe` | On-device captions with WhisperKit (falls back to the hf-mirror host when needed) |
| `App` | SwiftUI interface |

## License

[MIT](LICENSE). Speech recognition is powered by [WhisperKit](https://github.com/argmaxinc/WhisperKit) (MIT) and OpenAI's Whisper models.
