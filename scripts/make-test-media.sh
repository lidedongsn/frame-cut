#!/usr/bin/env bash
# 用 ffmpeg 生成测试素材到 TestMedia/（不入库）
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p TestMedia
F="ffmpeg -hide_banner -loglevel error -y"
$F -f lavfi -i testsrc2=size=1920x1080:rate=30:duration=10 -f lavfi -i sine=frequency=440:duration=10 \
   -c:v h264_videotoolbox -b:v 8M -pix_fmt yuv420p -c:a aac -shortest TestMedia/landscape_10s.mp4
# 竖拍：画面上半红下半蓝（1920x1080 存储），带 rotate=90 元数据 → 显示为 1080x1920
$F -f lavfi -i "color=red:size=1920x540:rate=30:duration=6" -f lavfi -i "color=blue:size=1920x540:rate=30:duration=6" \
   -f lavfi -i sine=frequency=660:duration=6 \
   -filter_complex "[0][1]vstack[v]" -map "[v]" -map 2 -c:v h264_videotoolbox -b:v 4M -pix_fmt yuv420p -c:a aac -shortest \
   TestMedia/_portrait_raw.mov
$F -display_rotation:v:0 -90 -i TestMedia/_portrait_raw.mov -c copy TestMedia/portrait_rotated_6s.mov
rm TestMedia/_portrait_raw.mov
$F -f lavfi -i "sine=frequency=330:duration=20" -c:a aac TestMedia/tone_20s.m4a
$F -f lavfi -i "testsrc=size=1600x1200:rate=1:duration=1" -frames:v 1 TestMedia/photo.jpg
ls -la TestMedia
