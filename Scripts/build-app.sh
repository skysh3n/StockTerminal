#!/bin/zsh
# 组装正规 .app bundle：可执行文件仍为 StockTerminal，安装包名为「量化终端.app」。
# 桌面若在 iCloud，直接在 build/ 上 codesign 会因 fileprovider 扩展属性失败，故在 /tmp 签名再拷回。
# 默认安装到 /Applications/量化终端.app（失败则 ~/Applications）。
set -e
cd "$(dirname "$0")/.."

EXEC=StockTerminal          # Mach-O / SwiftPM 产物名（勿改，需与 CFBundleExecutable 一致）
BUNDLE_NAME="量化终端"       # .app 文件夹名 → Dock / Finder / Launchpad 显示名
swift build -c release
BIN="$(swift build -c release --show-bin-path)/$EXEC"
OUT="build/${BUNDLE_NAME}.app"
STAGE="$(mktemp -d /tmp/StockTerminal-app.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT

# 图标缺失时自动从矢量脚本生成
if [[ ! -f Resources/AppIcon.icns ]]; then
    swift Scripts/make-icon.swift build/AppIcon.iconset
    iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns
fi

APP_STAGE="$STAGE/${BUNDLE_NAME}.app"
mkdir -p "$APP_STAGE/Contents/MacOS" "$APP_STAGE/Contents/Resources"
mkdir -p "$APP_STAGE/Contents/Resources/zh-Hans.lproj" "$APP_STAGE/Contents/Resources/Base.lproj"
cp "$BIN" "$APP_STAGE/Contents/MacOS/$EXEC"
cp Resources/Info.plist "$APP_STAGE/Contents/Info.plist"
cp Resources/zh-Hans.lproj/InfoPlist.strings "$APP_STAGE/Contents/Resources/zh-Hans.lproj/"
cp Resources/Base.lproj/InfoPlist.strings "$APP_STAGE/Contents/Resources/Base.lproj/"
if [[ -f Resources/AppIcon.icns ]]; then
    cp Resources/AppIcon.icns "$APP_STAGE/Contents/Resources/"
fi
find "$STAGE" -name '.DS_Store' -delete
xattr -cr "$APP_STAGE" 2>/dev/null || true
if ! codesign --force --sign - "$APP_STAGE"; then
    echo "❌ codesign 失败（/tmp 暂存仍无法签名）"; exit 1
fi

rm -rf "$OUT" "build/${EXEC}.app"
mkdir -p build
ditto "$APP_STAGE" "$OUT"

# 安装到 Applications；顺带清掉旧的英文包名
INSTALL="/Applications/${BUNDLE_NAME}.app"
rm -rf "/Applications/${EXEC}.app" 2>/dev/null || true
rm -rf "$HOME/Applications/${EXEC}.app" 2>/dev/null || true
if ! ditto "$APP_STAGE" "$INSTALL" 2>/dev/null; then
    mkdir -p "$HOME/Applications"
    INSTALL="$HOME/Applications/${BUNDLE_NAME}.app"
    ditto "$APP_STAGE" "$INSTALL"
    echo "⚠️  /Applications 不可写，已安装到 $INSTALL"
else
    echo "✅ 已安装 $INSTALL"
fi

# 刷新 Launch Services，避免 Dock/Launchpad 仍缓存 StockTerminal
LSREG="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
[[ -x "$LSREG" ]] && "$LSREG" -f "$INSTALL" >/dev/null 2>&1 || true

echo "✅ $OUT"
echo "   open \"$INSTALL\""
