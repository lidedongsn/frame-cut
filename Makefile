# FrameCut 常用命令。make help 查看全部。
PKG       := Packages/FrameCutKit
DD        := build/DD
APP_DEBUG := $(DD)/Build/Products/Debug/FrameCut.app
APP_REL   := $(DD)/Build/Products/Release/FrameCut.app

.PHONY: help setup project build release run run-release dmg icon test test-media bench check clean clean-all

help:            ## 列出命令
	@grep -E '^[a-z-]+:.*##' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  make %-12s %s\n", $$1, $$2}'

setup:           ## 安装依赖（XcodeGen、ffmpeg）并生成工程
	@command -v xcodegen >/dev/null || brew install xcodegen
	@command -v ffmpeg >/dev/null || brew install ffmpeg
	$(MAKE) project

project:         ## 由 project.yml 生成 FrameCut.xcodeproj
	xcodegen generate

build: project   ## 调试构建
	xcodebuild -project FrameCut.xcodeproj -scheme FrameCut -configuration Debug -derivedDataPath $(DD) build -quiet

release: project ## 发布构建（日常使用推荐，性能最好）
	xcodebuild -project FrameCut.xcodeproj -scheme FrameCut -configuration Release -derivedDataPath $(DD) build -quiet
	@echo "→ $(APP_REL)"

run: build       ## 构建并打开调试版
	open $(APP_DEBUG)

run-release: release ## 构建并打开发布版
	open $(APP_REL)

dmg: release     ## 打包安装包 build/FrameCut-版本号.dmg（可发给别人）
	./scripts/make-dmg.sh

icon:            ## 由 scripts/make-icon.swift 重新生成应用图标
	swift scripts/make-icon.swift App/Assets.xcassets/AppIcon.appiconset

test-media:      ## 生成测试素材到 TestMedia/（需要 ffmpeg）
	./scripts/make-test-media.sh

test:            ## 运行全部单元测试
	@test -f TestMedia/landscape_10s.mp4 || $(MAKE) test-media
	swift test --package-path $(PKG)

bench:           ## 性能实测（导出、分阶段、编码器）
	FC_BENCH=1 swift test -c release --package-path $(PKG) --filter 'Benchmark'

check: test build ## 提交前检查：测试 + 构建
	@echo "✓ 测试与构建通过"

clean:           ## 删除构建产物
	rm -rf $(DD) $(PKG)/.build

clean-all: clean ## 再删除测试素材与生成的 Xcode 工程
	rm -rf TestMedia FrameCut.xcodeproj
