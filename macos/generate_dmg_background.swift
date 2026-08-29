#!/usr/bin/env swift
import AppKit
import CoreGraphics

let width: CGFloat = 660
let height: CGFloat = 400

func readVersion() -> String {
    let path = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("version.json").path
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let version = json["version"] as? String else {
        return "?"
    }
    return version
}

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: red / 255, green: green / 255, blue: blue / 255, alpha: alpha)
}

func drawCentered(_ text: String, y: CGFloat, attributes: [NSAttributedString.Key: Any]) {
    let value = text as NSString
    let size = value.size(withAttributes: attributes)
    value.draw(at: NSPoint(x: (width - size.width) / 2, y: y), withAttributes: attributes)
}

let appVersion = readVersion()
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(width),
    pixelsHigh: Int(height),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
)!

let graphics = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = graphics
let ctx = graphics.cgContext
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

// Quiet, deep background: Finder's app icon remains the brightest object.
let baseGradient = CGGradient(
    colorsSpace: colorSpace,
    colors: [color(8, 13, 32).cgColor, color(15, 24, 54).cgColor] as CFArray,
    locations: [0, 1]
)!
ctx.drawLinearGradient(
    baseGradient,
    start: CGPoint(x: 0, y: 0),
    end: CGPoint(x: width, y: height),
    options: []
)

// Nabira-specific signature: a restrained field of keyboard keys.
ctx.setLineWidth(1)
for row in 0..<5 {
    let keyWidth: CGFloat = 54
    let gap: CGFloat = 10
    let offset: CGFloat = row.isMultiple(of: 2) ? -22 : 10
    for column in 0..<12 {
        let rect = CGRect(
            x: offset + CGFloat(column) * (keyWidth + gap),
            y: 92 + CGFloat(row) * 54,
            width: keyWidth,
            height: 36
        )
        let key = NSBezierPath(roundedRect: rect, xRadius: 9, yRadius: 9)
        color(124, 145, 255, 0.026).setFill()
        color(151, 167, 255, 0.045).setStroke()
        key.fill()
        key.stroke()
    }
}

func drawGlow(center: CGPoint, radius: CGFloat, rgb: (CGFloat, CGFloat, CGFloat), alpha: CGFloat) {
    let colors = [
        color(rgb.0, rgb.1, rgb.2, alpha).cgColor,
        color(rgb.0, rgb.1, rgb.2, 0).cgColor,
    ] as CFArray
    let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0, 1])!
    ctx.drawRadialGradient(
        gradient,
        startCenter: center,
        startRadius: 0,
        endCenter: center,
        endRadius: radius,
        options: []
    )
}

// Light anchors beneath Finder's two draggable icons.
drawGlow(center: CGPoint(x: 170, y: 190), radius: 126, rgb: (82, 104, 255), alpha: 0.24)
drawGlow(center: CGPoint(x: 490, y: 190), radius: 118, rgb: (66, 182, 219), alpha: 0.12)

let titleAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 31, weight: .bold),
    .foregroundColor: color(247, 249, 255),
    .kern: -0.7,
]
drawCentered("Nabira", y: 337, attributes: titleAttributes)

let subtitleAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 13, weight: .medium),
    .foregroundColor: color(171, 183, 226),
]
drawCentered("Печатайте мысль, а не раскладку", y: 311, attributes: subtitleAttributes)

let badgeRect = CGRect(x: 566, y: 338, width: 58, height: 24)
let badge = NSBezierPath(roundedRect: badgeRect, xRadius: 12, yRadius: 12)
color(103, 124, 255, 0.12).setFill()
color(145, 159, 255, 0.22).setStroke()
badge.fill()
badge.stroke()
let versionAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .semibold),
    .foregroundColor: color(190, 200, 255),
]
let versionText = "v\(appVersion)" as NSString
let versionSize = versionText.size(withAttributes: versionAttributes)
versionText.draw(
    at: NSPoint(x: badgeRect.midX - versionSize.width / 2, y: badgeRect.midY - versionSize.height / 2),
    withAttributes: versionAttributes
)

// The conversion rail also acts as the drag direction.
let railY: CGFloat = 191
ctx.setLineCap(.round)
ctx.setLineWidth(3)
ctx.setStrokeColor(color(111, 131, 255, 0.52).cgColor)
ctx.move(to: CGPoint(x: 257, y: railY))
ctx.addLine(to: CGPoint(x: 393, y: railY))
ctx.strokePath()

ctx.setFillColor(color(124, 145, 255, 0.92).cgColor)
ctx.move(to: CGPoint(x: 407, y: railY))
ctx.addLine(to: CGPoint(x: 388, y: railY + 12))
ctx.addLine(to: CGPoint(x: 388, y: railY - 12))
ctx.closePath()
ctx.fillPath()

let caret = NSBezierPath(
    roundedRect: CGRect(x: 326, y: 181, width: 5, height: 20),
    xRadius: 2.5,
    yRadius: 2.5
)
color(228, 233, 255, 0.9).setFill()
caret.fill()

let hintAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
    .foregroundColor: color(215, 222, 250),
]
drawCentered("Перетащите Nabira в Applications", y: 74, attributes: hintAttributes)

let footerAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 10, weight: .medium),
    .foregroundColor: color(119, 132, 176),
]
drawCentered("nabira.site", y: 22, attributes: footerAttributes)

NSGraphicsContext.current = nil
let pngData = rep.representation(using: .png, properties: [:])!
let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "dmg_background.png"
try pngData.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
print("Generated: \(outputPath) (\(Int(width))x\(Int(height)))")
