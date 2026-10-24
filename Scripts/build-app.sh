#!/bin/zsh
# 组装正规 .app bundle：独立进程名 / Dock 图标 / 中文显示名 / ad-hoc 签名（本机可运行）
# 桌面若在 iCloud，直接在 build/ 上 codesign 会因 fileprovider 扩展属性失败，故在 /tmp 签名再拷回。
# 默认再安装到 /Applications/StockTerminal.app（失败则 ~/Applications），便于用户从启动台打开。
set -e
cd "$(dirname "$0")/.."

APP=StockTerminal
swift build -c release
BIN="$(swift build -c release --show-bin-path)/$APP"
OUT="build/$APP.app"
STAGE="$(mktemp -d /tmp/StockTerminal-app.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT

# 图标缺失时自动从矢量脚本生成
if [[ ! -f Resources/AppIcon.icns ]]; then
    swift Scripts/make-icon.swift build/AppIcon.iconset
    iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns
fi

mkdir -p "$STAGE/$APP.app/Contents/MacOS" "$STAGE/$APP.app/Contents/Resources"
cp "$BIN" "$STAGE/$APP.app/Contents/MacOS/$APP"
cp Resources/Info.plist "$STAGE/$APP.app/Contents/Info.plist"
if [[ -f Resources/AppIcon.icns ]]; then
    cp Resources/AppIcon.icns "$STAGE/$APP.app/Contents/Resources/"
fi
find "$STAGE" -name '.DS_Store' -delete
xattr -cr "$STAGE/$APP.app" 2>/dev/null || true
if ! codesign --force --sign - "$STAGE/$APP.app"; then
    echo "❌ codesign 失败（/tmp 暂存仍无法签名）"; exit 1
fi

rm -rf "$OUT"
mkdir -p build
ditto "$STAGE/$APP.app" "$OUT"

# 安装到 Applications（显示名仍为「量化终端」）
INSTALL="/Applications/$APP.app"
if ! ditto "$STAGE/$APP.app" "$INSTALL" 2>/dev/null; then
    mkdir -p "$HOME/Applications"
    INSTALL="$HOME/Applications/$APP.app"
    ditto "$STAGE/$APP.app" "$INSTALL"
    echo "⚠️  /Applications 不可写，已安装到 $INSTALL"
else
    echo "✅ 已安装 $INSTALL"
fi

echo "✅ $OUT"
echo "   open \"$INSTALL\""
