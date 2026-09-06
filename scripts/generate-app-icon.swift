#!/usr/bin/env swift
import AppKit

/// 単色背景に棒グラフ風アイコンを載せた macOS 用 AppIcon 一式を書き出す。
/// 実行: swift scripts/generate-app-icon.swift

let destinations: [URL] = {
    if CommandLine.arguments.count > 1 {
        return CommandLine.arguments.dropFirst().map { URL(fileURLWithPath: $0) }
    }
    return [
        URL(fileURLWithPath: "App/Assets.xcassets/AppIcon.appiconset"),
        URL(fileURLWithPath: "WidgetExtension/Assets.xcassets/AppIcon.appiconset"),
    ]
}()

let macSizes: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

let catalogIOSSizes: [(name: String, pixels: Int)] = [
    ("AppIcon60x60@2x.png", 120),
    ("AppIcon60x60@3x.png", 180),
    ("AppIcon76x76@2x.png", 152),
]

let resourceIOSSizes: [(name: String, pixels: Int)] = catalogIOSSizes + [
    ("AppIcon76x76@2x~ipad.png", 152),
]

let background = NSColor(srgbRed: 0x1A / 255, green: 0x6B / 255, blue: 0xF2 / 255, alpha: 1)

func render(pixels: Int) -> Data {
    let size = CGFloat(pixels)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil,
        width: pixels,
        height: pixels,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        fatalError("CGContext")
    }

    ctx.setFillColor(background.cgColor)
    ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
    drawBars(in: ctx, size: size)

    guard let cgImage = ctx.makeImage() else { fatalError("makeImage") }
    let rep = NSBitmapImageRep(cgImage: cgImage)
    guard let data = rep.representation(using: .png, properties: [:]) else { fatalError("png") }
    return data
}

func drawBars(in ctx: CGContext, size: CGFloat) {
    ctx.saveGState()
    ctx.translateBy(x: size / 2, y: size / 2)
    let scale = size * 0.72 / 84
    ctx.scaleBy(x: scale, y: scale)
    ctx.setFillColor(NSColor.white.cgColor)

    let bars: [(x: CGFloat, h: CGFloat)] = [
        (-30, 28),
        (-10, 48),
        (10, 38),
        (30, 58)
    ]
    let width: CGFloat = 14
    for bar in bars {
        let rect = CGRect(x: bar.x - width / 2, y: -30, width: width, height: bar.h)
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 4, cornerHeight: 4, transform: nil))
        ctx.fillPath()
    }
    ctx.restoreGState()
}

let contents: [String: Any] = [
    "images": (macSizes + catalogIOSSizes).map { item -> [String: Any] in
        if item.name.hasPrefix("AppIcon60") {
            return [
                "filename": item.name,
                "idiom": "iphone",
                "scale": item.name.contains("@3x") ? "3x" : "2x",
                "size": "60x60"
            ]
        }
        if item.name.hasPrefix("AppIcon76") {
            return [
                "filename": item.name,
                "idiom": "ipad",
                "scale": "2x",
                "size": "76x76"
            ]
        }
        let base = item.name
            .replacingOccurrences(of: "@2x.png", with: "")
            .replacingOccurrences(of: ".png", with: "")
            .replacingOccurrences(of: "icon_", with: "")
        let parts = base.split(separator: "x")
        let side = parts.first.map(String.init) ?? "16"
        let scale = item.name.contains("@2x") ? "2x" : "1x"
        return [
            "filename": item.name,
            "idiom": "mac",
            "scale": scale,
            "size": "\(side)x\(side)"
        ]
    },
    "info": ["author": "xcode", "version": 1]
]

for dest in destinations {
    try? FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
    for item in macSizes + catalogIOSSizes {
        let data = render(pixels: item.pixels)
        try! data.write(to: dest.appendingPathComponent(item.name))
    }
    let json = try! JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    try! json.write(to: dest.appendingPathComponent("Contents.json"))
    print("wrote \(dest.path)")
}

// CFBundleIconFiles 用のルート Resources 配置はビルド時 Assets から拾うので、
// 追加のコピー先があればここに書く。
for item in resourceIOSSizes {
    let data = render(pixels: item.pixels)
    let appRes = URL(fileURLWithPath: "App/Resources")
    let widgetRes = URL(fileURLWithPath: "WidgetExtension/Resources")
    for dir in [appRes, widgetRes] {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try! data.write(to: dir.appendingPathComponent(item.name))
    }
}

print("done")
