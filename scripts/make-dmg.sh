#!/bin/bash
# 打包 FrameCut 安装包（.dmg）：发布构建 → 本机签名 → 带“拖到应用程序”快捷方式和首次打开说明的磁盘映像。
# 未使用 Apple 开发者账号签名公证，其他 Mac 首次打开需在「系统设置 → 隐私与安全性」中放行一次。
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/DD/Build/Products/Release/FrameCut.app"
[ -d "$APP" ] || { echo "找不到 $APP，请先 make release"; exit 1; }

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
OUT="build/FrameCut-$VERSION.dmg"
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

cp -R "$APP" "$STAGE/"
# 本机临时签名（Apple 芯片要求 App 必须有签名）；--deep 覆盖内嵌的框架与资源包
codesign --force --deep --sign - "$STAGE/FrameCut.app"
codesign --verify --deep --strict "$STAGE/FrameCut.app"
ln -s /Applications "$STAGE/应用程序"

cat > "$STAGE/首次打开说明.txt" <<TXT
FrameCut $VERSION 安装说明

1. 把 FrameCut 拖到「应用程序」文件夹。
2. 第一次打开时，系统会提示“Apple 无法验证 FrameCut 是否包含恶意软件”，点「完成」。
   （FrameCut 是免费软件，还没有向 Apple 付费注册签名，所以会有这个提示。）
3. 打开「系统设置 → 隐私与安全性」，往下翻到“安全性”一栏，
   找到“已阻止使用 FrameCut”，点「仍要打开」，输入开机密码确认。
4. 之后就可以像普通 App 一样直接打开了，这一步只需要做一次。

系统要求：macOS 14 或更新，Apple 芯片（M1 / M2 / M3 / M4）。
TXT

rm -f "$OUT"
hdiutil create -volname "FrameCut $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -imagekey zlib-level=9 -ov "$OUT" >/dev/null
echo "→ $OUT ($(du -h "$OUT" | cut -f1))"
