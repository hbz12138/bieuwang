#!/bin/bash
# 一条命令做完交付前自检。任何一项失败，退出码非 0。
set -uo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD="$ROOT/build"
APP="$BUILD/别忘.app"
fail=0

green() { printf "\033[32m%s\033[0m\n" "$1"; }
red()   { printf "\033[31m%s\033[0m\n" "$1"; }

CORE_SOURCES=$(find "$ROOT/Sources/Domain" "$ROOT/Sources/Persistence" \
  "$ROOT/Sources/Integrations" "$ROOT/Sources/Application" \
  "$ROOT/Sources/UI" "$ROOT/Sources/App" \
  -name '*.swift' ! -path '*/App/main.swift' | sort)

FRAMEWORKS="-framework AppKit -framework EventKit -framework UserNotifications -framework ServiceManagement -framework UniformTypeIdentifiers"

echo "▸ 1/5 编译 App"
if "$ROOT/build.sh" >/tmp/bw-build.log 2>&1; then
  green "   通过"
else
  red "   编译失败，详见 /tmp/bw-build.log"
  tail -20 /tmp/bw-build.log
  exit 1
fi

echo "▸ 2/5 代码签名与包结构"
# 不用 --strict：Finder 会给 .app 目录加 com.apple.FinderInfo，
# --strict 会因此报错，但签名本身完全有效（--verify 才是权威判断）。
if codesign --verify "$APP" 2>/dev/null \
   && [ -x "$APP/Contents/MacOS/别忘" ] \
   && plutil -lint "$APP/Contents/Info.plist" >/dev/null 2>&1; then
  green "   通过"
else
  red "   签名或包结构有问题"
  fail=1
fi

echo "▸ 3/5 界面布局"
if swiftc -swift-version 5 -Onone $FRAMEWORKS \
  -o "$BUILD/layoutcheck" $CORE_SOURCES "$ROOT/Tools/LayoutCheck/main.swift" 2>/tmp/bw-layout.log; then
  LAYOUT=$("$BUILD/layoutcheck" 2>&1)
  AMBIGUOUS=$(echo "$LAYOUT" | sed -n 's/.*模糊布局数量： *\([0-9]*\).*/\1/p')
  if [ "${AMBIGUOUS:-x}" = "0" ]; then
    green "   通过（0 个模糊约束）"
  else
    red "   有 ${AMBIGUOUS:-?} 个模糊约束，界面可能错位"
    echo "$LAYOUT" | grep -E "AMBIGUOUS|ZERO" | head -10
    fail=1
  fi
else
  red "   布局自检编译失败，详见 /tmp/bw-layout.log"
  fail=1
fi

echo "▸ 4/5 功能测试"
if swiftc -swift-version 5 -Onone $FRAMEWORKS \
  -o "$BUILD/tests" $CORE_SOURCES "$ROOT/Tools/Tests/main.swift" 2>/tmp/bw-tests.log; then
  if "$BUILD/tests" >/tmp/bw-tests-run.log 2>&1; then
    SUMMARY=$(grep -E "^通过" /tmp/bw-tests-run.log | tail -1)
    green "   通过（${SUMMARY}）"
  else
    red "   有测试失败："
    grep "❌" /tmp/bw-tests-run.log | sed 's/^/     /'
    fail=1
  fi
else
  red "   测试编译失败，详见 /tmp/bw-tests.log"
  tail -10 /tmp/bw-tests.log
  fail=1
fi

echo "▸ 5/5 启动冒烟"
if pgrep -f "$APP/Contents/MacOS/别忘" >/dev/null 2>&1; then
  green "   已在运行，跳过（避免打断你正在用的实例）"
else
  open "$APP"
  sleep 3
  if pgrep -f "$APP/Contents/MacOS/别忘" >/dev/null 2>&1; then
    green "   启动正常"
    pkill -f "$APP/Contents/MacOS/别忘" >/dev/null 2>&1
    sleep 0.5
    echo "   （冒烟后已退出，用 make run 重新启动）"
  else
    red "   启动后立刻退出，可能有崩溃"
    fail=1
  fi
fi

echo
if [ "$fail" -eq 0 ]; then
  green "全部通过。可以交付。"
else
  red "有检查未通过，先修再交付。"
fi
exit "$fail"
