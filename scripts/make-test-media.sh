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

# HDR 测试素材：四条竖向灰度带，信号值精确可控（10 位 HEVC）
# HLG 信号：0.50 / 0.75（参考白 203 尼特）/ 0.86（约 400 尼特）/ 1.00（1000 尼特）
# PQ 信号：100 / 203 / 400 / 1000 尼特
python3 - <<'PY'
import struct
W, H = 1920, 1080
def pq(nits):
    m1, m2, c1, c2, c3 = 0.1593017578125, 78.84375, 0.8359375, 18.8515625, 18.6875
    y = (nits / 10000) ** m1
    return ((c1 + c2 * y) / (1 + c3 * y)) ** m2
for name, bands in [("hlg", [0.50, 0.75, 0.86, 1.00]), ("pq", [pq(100), pq(203), pq(400), pq(1000)])]:
    row = b"".join(struct.pack("<H", int(round(bands[x * 4 // W] * 65535))) for x in range(W))
    with open(f"TestMedia/_{name}.gray16", "wb") as f:
        f.write(row * H)
PY
for kind in hlg pq; do
  trc=$([ $kind = hlg ] && echo arib-std-b67 || echo smpte2084)
  $F -f rawvideo -pix_fmt gray16le -s 1920x1080 -r 30 -stream_loop 59 -i TestMedia/_$kind.gray16 -f lavfi -i sine=frequency=500:duration=2 \
     -vf "scale=out_range=tv:out_color_matrix=bt2020,format=p010le,setparams=color_primaries=bt2020:color_trc=$trc:colorspace=bt2020nc:range=tv" -c:v hevc_videotoolbox -profile:v main10 -b:v 20M -tag:v hvc1 \
     -color_primaries bt2020 -color_trc $trc -colorspace bt2020nc -color_range tv -c:a aac -shortest TestMedia/${kind}_bands_2s.mov
  rm TestMedia/_$kind.gray16
done
ls -la TestMedia/*bands*
