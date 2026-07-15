# LCCAD ビルド・インストール用 Makefile
#
# よく使うもの:
#   make install   — Release ビルドして /Applications/LCCAD.app を入れ替え
#   make test      — テスト実行

APP_NAME     := LCCAD
PROJECT      := LCCAD.xcodeproj
SCHEME       := LCCAD
DERIVED_DATA := build/DerivedData
RELEASE_APP  := $(DERIVED_DATA)/Build/Products/Release/$(APP_NAME).app
INSTALL_DIR  := /Applications

.DEFAULT_GOAL := help
.PHONY: help generate build test release install clean

help: ## このヘルプを表示
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  make %-10s %s\n", $$1, $$2}'

generate: ## XcodeGen で .xcodeproj を生成
	xcodegen generate

build: generate ## Debug ビルド
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug build

test: generate ## テスト実行
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) test

release: generate ## Release ビルド（成果物: build/DerivedData/Build/Products/Release/LCCAD.app）
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release \
		-derivedDataPath $(DERIVED_DATA) build

install: release ## Release ビルドして /Applications に入れ替え
	@if pgrep -xq $(APP_NAME); then \
		echo "⚠️  $(APP_NAME) が起動中です。終了してから再実行してください。"; \
		exit 1; \
	fi
	rm -rf $(INSTALL_DIR)/$(APP_NAME).app
	ditto $(RELEASE_APP) $(INSTALL_DIR)/$(APP_NAME).app
	@echo "✅ $(INSTALL_DIR)/$(APP_NAME).app を更新しました" \
		"(v$$(defaults read $(INSTALL_DIR)/$(APP_NAME).app/Contents/Info CFBundleShortVersionString))"

clean: ## ビルド成果物 (build/) を削除
	rm -rf $(DERIVED_DATA)
