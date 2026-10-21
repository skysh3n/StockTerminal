import Foundation
import CoreGraphics
import ImageIO

// 量化终端 App 图标生成器：矢量绘制 → 全尺寸 iconset PNG
// 设计语言与 App 一致：深色 squircle 底（bgBase/bgElevated）+ 红涨绿跌蜡烛 + 金色趋势线（accent）
// 用法：swift Scripts/make-icon.swift <iconset 输出目录>

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build/AppIcon.iconset"

func hex(_ h: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((h >> 16) & 0xFF) / 255,
            green: CGFloat((h >> 8) & 0xFF) / 255,
            blue: CGFloat(h & 0xFF) / 255, alpha: a)
}

struct Candle {
    let x: CGFloat          // 中心 x（0..1）
    let bodyTop: CGFloat    // 实体上沿（0..1，自上而下）
    let bodyBottom: CGFloat
    let wickTop: CGFloat
    let wickBottom: CGFloat
    let up: Bool
}

let candles: [Candle] = [
    .init(x: 0.25, bodyTop: 0.62, bodyBottom: 0.47, wickTop: 0.68, wickBottom: 0.42, up: true),
    .init(x: 0.41, bodyTop: 0.45, bodyBottom: 0.58, wickTop: 0.40, wickBottom: 0.64, up: false),
    .init(x: 0.57, bodyTop: 0.57, bodyBottom: 0.35, wickTop: 0.61, wickBottom: 0.29, up: true),
    .init(x: 0.73, bodyTop: 0.35, bodyBottom: 0.23, wickTop: 0.39, wickBottom: 0.17, up: true),
]

/// 金色趋势线折点（收盘连线并向前延伸）
let trend: [(CGFloat, CGFloat)] = [
    (0.15, 0.68), (0.25, 0.51), (0.41, 0.55), (0.57, 0.37), (0.73, 0.25), (0.85, 0.19),
]

func draw(size: Int) -> CGImage {
    let S = CGFloat(size)
    let ctx = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    // 设计坐标：分数制，y 自上而下；CG 坐标 y 自下而上
    func X(_ f: CGFloat) -> CGFloat { f * S }
    func Y(_ f: CGFloat) -> CGFloat { (1 - f) * S }

    // squircle 裁切
    let corner = S * 0.225
    let squircle = CGPath(roundedRect: CGRect(x: 0, y: 0, width: S, height: S),
                          cornerWidth: corner, cornerHeight: corner, transform: nil)
    ctx.addPath(squircle)
    ctx.clip()

    // 背景：上浅下深垂直渐变
    let bg = CGGradient(colorsSpace: nil,
                        colors: [hex(0x1A2029), hex(0x0B0E14)] as CFArray,
                        locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: S), end: CGPoint(x: 0, y: 0), options: [])

    // 金色辉光（趋势线背后）
    let glowCenter = CGPoint(x: X(0.62), y: Y(0.36))
    let glow = CGGradient(colorsSpace: nil,
                          colors: [hex(0xE0A540, 0.22), hex(0xE0A540, 0)] as CFArray,
                          locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: glowCenter, startRadius: 0,
                           endCenter: glowCenter, endRadius: S * 0.55, options: [])

    // 蜡烛：影线 + 圆角实体
    let cw = S * 0.10
    for c in candles {
        let color = c.up ? hex(0xF23645) : hex(0x089981)
        ctx.setStrokeColor(color)
        ctx.setLineWidth(max(S * 0.02, 1))
        ctx.setLineCap(.round)
        ctx.move(to: CGPoint(x: X(c.x), y: Y(c.wickTop)))
        ctx.addLine(to: CGPoint(x: X(c.x), y: Y(c.wickBottom)))
        ctx.strokePath()
        let body = CGRect(x: X(c.x) - cw / 2, y: Y(c.bodyBottom),
                          width: cw, height: (c.bodyBottom - c.bodyTop) * S)
        ctx.setFillColor(color)
        ctx.addPath(CGPath(roundedRect: body, cornerWidth: cw * 0.2, cornerHeight: cw * 0.2, transform: nil))
        ctx.fillPath()
    }

    // 金色趋势线：先宽描边做光晕，再实线
    let line = CGMutablePath()
    for (i, p) in trend.enumerated() {
        let pt = CGPoint(x: X(p.0), y: Y(p.1))
        if i == 0 { line.move(to: pt) } else { line.addLine(to: pt) }
    }
    ctx.setLineJoin(.round)
    ctx.setLineCap(.round)
    ctx.addPath(line)
    ctx.setStrokeColor(hex(0xE0A540, 0.28))
    ctx.setLineWidth(S * 0.08)
    ctx.strokePath()
    ctx.addPath(line)
    ctx.setStrokeColor(hex(0xE0A540))
    ctx.setLineWidth(S * 0.034)
    ctx.strokePath()

    // 线端金点（空心环）
    let end = CGPoint(x: X(0.85), y: Y(0.19))
    ctx.setFillColor(hex(0xE0A540))
    ctx.fillEllipse(in: CGRect(x: end.x - S * 0.048, y: end.y - S * 0.048,
                               width: S * 0.096, height: S * 0.096))
    ctx.setFillColor(hex(0x0B0E14))
    ctx.fillEllipse(in: CGRect(x: end.x - S * 0.019, y: end.y - S * 0.019,
                               width: S * 0.038, height: S * 0.038))

    // 顶部柔光
    let gloss = CGGradient(colorsSpace: nil,
                           colors: [hex(0xFFFFFF, 0.07), hex(0xFFFFFF, 0)] as CFArray,
                           locations: [0, 1])!
    ctx.drawLinearGradient(gloss, start: CGPoint(x: 0, y: S), end: CGPoint(x: 0, y: S * 0.55), options: [])

    // 内描边（borderStrong）
    let inset = CGPath(roundedRect: CGRect(x: S * 0.005, y: S * 0.005,
                                           width: S * 0.99, height: S * 0.99),
                       cornerWidth: corner * 0.98, cornerHeight: corner * 0.98, transform: nil)
    ctx.addPath(inset)
    ctx.setStrokeColor(hex(0x2E3746, 0.9))
    ctx.setLineWidth(max(S * 0.006, 1))
    ctx.strokePath()

    return ctx.makeImage()!
}

func write(_ img: CGImage, to url: URL) {
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
        fatalError("cannot create image destination \(url)")
    }
    CGImageDestinationAddImage(dest, img, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("cannot write \(url)") }
}

let fm = FileManager.default
try? fm.createDirectory(atPath: outDir, withIntermediateDirectories: true)

let sizes: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]
var cache: [Int: CGImage] = [:]
for (name, px) in sizes {
    if cache[px] == nil { cache[px] = draw(size: px) }
    write(cache[px]!, to: URL(fileURLWithPath: outDir).appendingPathComponent(name))
}
print("✅ iconset → \(outDir)（\(sizes.count) 个 PNG）")
