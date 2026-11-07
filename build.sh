#!/bin/bash
# 构建「别忘」.app
#
# ⚠️ 架构说明：本脚本产出的是 **arm64（Apple Silicon）单架构** 二进制，
#    Intel Mac（x86_64）无法运行。
#    如需支持 Intel，把 swiftc 换成 -target x86_64-apple-macosx13.0 各编一份，
#    再用 lipo -create 合成 universal 包。注意：本机没有 Intel 真机验证过。
#
# 许可证：GPL-3.0-or-later，见 LICENSE。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="别忘"
BUILD="$ROOT/build"
APP="$BUILD/$APP_NAME.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "▸ 编译"
swiftc -swift-version 5 -O \
  -framework AppKit -framework EventKit \
  -framework UserNotifications -framework ServiceManagement -framework UniformTypeIdentifiers \
  -o "$APP/Contents/MacOS/$APP_NAME" \
  $(find "$ROOT/Sources" -name '*.swift' | sort)

echo "▸ 组装"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
if [ -f "$ROOT/Resources/AppIcon.icns" ]; then
  cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "▸ 签名（本地临时签名）"
# 新建的文件可能带着 FinderInfo / provenance 之类扩展属性，codesign 会拒绝；
# 清一次不行就清两次再签。
xattr -cr "$APP" 2>/dev/null || true
if ! codesign --force --deep --sign - "$APP" 2>/tmp/bieuwang-sign.log; then
  xattr -cr "$APP" 2>/dev/null || true
  if ! codesign --force --deep --sign - "$APP" 2>>/tmp/bieuwang-sign.log; then
    echo "  签名失败，见 /tmp/bieuwang-sign.log"
    sed 's/^/  /' /tmp/bieuwang-sign.log
    exit 1
  fi
fi

echo "▸ 打包 dmg"
DMG="$BUILD/别忘.dmg"
rm -f "$DMG"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "别忘" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

echo "▸ 完成"
echo "  App: $APP"
echo "  安装包: $DMG"
