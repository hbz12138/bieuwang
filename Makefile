# 日常只用这几条命令

SHELL := /bin/bash
ROOT := $(shell pwd)
APP  := $(ROOT)/build/别忘.app
DMG  := $(ROOT)/build/别忘.dmg

.PHONY: help app run dmg check fmt clean where

help:
	@echo "make app     编译 .app"
	@echo "make run     编译并重启 App（改完代码用这个）"
	@echo "make dmg     编译并打安装包"
	@echo "make check   全部自检：编译 / 签名 / 布局 / 按钮接线"
	@echo "make fmt     用 swift-format 格式化源码"
	@echo "make where   打印当前 SDK 和编译器路径"
	@echo "make clean   删掉 build/"

app:
	@./build.sh

run: app
	@-pkill -f "$(APP)/Contents/MacOS/别忘" 2>/dev/null; sleep 0.5
	@open "$(APP)"
	@echo "已重启：$(APP)"

dmg: app
	@echo "安装包：$(DMG)"

check:
	@./verify.sh

fmt:
	@swift-format format --in-place --recursive Sources Tools || true

where:
	@echo "SDK:    $$(xcrun --sdk macosx --show-sdk-path)"
	@echo "编译器: $$(xcrun --find swiftc)"
	@echo "版本:   $$(swiftc --version | head -1)"

clean:
	@rm -rf build
	@echo "已清理 build/"
