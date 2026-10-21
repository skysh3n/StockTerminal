#!/bin/zsh
# 组装正规 .app bundle：独立进程名 / Dock 图标 / 中文显示名 / ad-hoc 签名（本机可运行）
set -e
cd "$(dirname "$0")/.."

APP=StockTerminal
swift build -c release
BIN="$(swift build -c release --show-bin-path)/$APP"
OUT="build/$APP.app"

# 图标缺失时自动从矢量脚本生成
if [[ ! -f Resources/AppIcon.icns ]]; then
    swift Scripts/make-icon.swift build/AppIcon.iconset
    iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns
fi

rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources"
cp "$BIN" "$OUT/Contents/MacOS/$APP"
cp Resources/Info.plist "$OUT/Contents/Info.plist"
if [[ -f Resources/AppIcon.icns ]]; then
    cp Resources/AppIcon.icns "$OUT/Contents/Resources/"
fi
# 清除扩展属性杂散（iCloud Desktop 的 fileprovider 标记 / FinderInfo），否则 codesign 拒绝签名。
# fileprovider 会在文件创建后异步补打标记，故用重试循环：清一次签一次，直到成功。
find "$OUT" -name '.DS_Store' -delete
SIGNED=0
for i in 1 2 3 4 5 6; do
    xattr -cr "$OUT" 2>/dev/null || true
    xattr -c "$OUT" 2>/dev/null || true
    if codesign --force --sign - "$OUT" 2>/dev/null; then
        SIGNED=1
        break
    fi
    sleep 0.8
done
if [[ $SIGNED -ne 1 ]]; then
    echo "❌ codesign 失败（扩展属性无法清除）"; exit 1
fi
echo "✅ $OUT  （双击运行，或 open $OUT）"
