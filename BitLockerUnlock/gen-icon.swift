#!/usr/bin/env swift
// gen-icon.swift — generate AppIcon.icns for the BitLocker Unlock app.
//
// Renders a rounded-square macOS-style app icon: a blue gradient background
// (matching SF Symbol "lock.shield.fill") with a centred white lock-shield
// glyph. Outputs a complete .iconset folder, then compiles it via iconutil
// into AppIcon.icns at the script's directory.
//
// Usage:
//   swift gen-icon.swift
//
// Re-run any time you want to regenerate. make-app.sh expects AppIcon.icns
// to live alongside it.

import AppKit
import CoreGraphics

// Run from the BitLockerUnlock package directory; write output into cwd.
let scriptDir = FileManager.default.currentDirectoryPath
let outDir    = scriptDir + "/icon.iconset"
let outIcns   = scriptDir + "/AppIcon.icns"

let fm = FileManager.default
try? fm.removeItem(atPath: outDir)
try fm.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func renderIcon(size: Int) -> Data {
    let s = CGFloat(size)
    let scale: CGFloat = 1
    let pxW = Int(s * scale)
    let pxH = Int(s * scale)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
    guard let ctx = CGContext(data: nil,
                              width: pxW, height: pxH,
                              bitsPerComponent: 8, bytesPerRow: 0,
                              space: colorSpace, bitmapInfo: bitmapInfo) else {
        fatalError("CGContext init failed at \(size)")
    }
    ctx.scaleBy(x: scale, y: scale)

    // Rounded square background with macOS-style ~22.5% corner radius.
    let radius: CGFloat = s * 0.225
    let bgPath = CGPath(roundedRect: CGRect(x: 0, y: 0, width: s, height: s),
                        cornerWidth: radius, cornerHeight: radius,
                        transform: nil)
    ctx.addPath(bgPath)
    ctx.clip()

    // Vertical gradient — system blue → deeper blue.
    let topColor    = CGColor(red: 0.04, green: 0.52, blue: 1.00, alpha: 1)
    let bottomColor = CGColor(red: 0.00, green: 0.31, blue: 0.86, alpha: 1)
    let gradient = CGGradient(colorsSpace: colorSpace,
                              colors: [topColor, bottomColor] as CFArray,
                              locations: [0, 1])!
    ctx.drawLinearGradient(gradient,
                           start: CGPoint(x: s/2, y: s),
                           end:   CGPoint(x: s/2, y: 0),
                           options: [])

    // Centred SF Symbol "lock.shield.fill" in white.
    let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: false)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = nsCtx

    let glyphSize = s * 0.55
    if let symbol = NSImage(systemSymbolName: "lock.shield.fill",
                            accessibilityDescription: nil) {
        let config = NSImage.SymbolConfiguration(pointSize: glyphSize, weight: .semibold)
        let configured = symbol.withSymbolConfiguration(config) ?? symbol
        let tinted = NSImage(size: configured.size)
        tinted.lockFocus()
        configured.draw(at: .zero, from: NSRect(origin: .zero, size: configured.size),
                        operation: .sourceOver, fraction: 1)
        NSColor.white.set()
        NSRect(origin: .zero, size: configured.size).fill(using: .sourceAtop)
        tinted.unlockFocus()
        let rect = NSRect(x: (s - tinted.size.width)/2,
                          y: (s - tinted.size.height)/2,
                          width: tinted.size.width,
                          height: tinted.size.height)
        tinted.draw(in: rect)
    }

    NSGraphicsContext.restoreGraphicsState()

    guard let cgImage = ctx.makeImage() else { fatalError("makeImage at \(size)") }
    let rep = NSBitmapImageRep(cgImage: cgImage)
    return rep.representation(using: .png, properties: [:])!
}

// Standard macOS iconset filename → pixel size mapping.
let outputs: [(name: String, size: Int)] = [
    ("icon_16x16.png",       16),
    ("icon_16x16@2x.png",    32),
    ("icon_32x32.png",       32),
    ("icon_32x32@2x.png",    64),
    ("icon_128x128.png",    128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png",    256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png",    512),
    ("icon_512x512@2x.png", 1024),
]

for (name, size) in outputs {
    let data = renderIcon(size: size)
    try data.write(to: URL(fileURLWithPath: "\(outDir)/\(name)"))
}

// Compile to .icns
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", outDir, "-o", outIcns]
try task.run()
task.waitUntilExit()
if task.terminationStatus != 0 {
    print("iconutil failed with exit \(task.terminationStatus)")
    exit(Int32(task.terminationStatus))
}

// Clean up the iconset directory (leave only the .icns)
try? fm.removeItem(atPath: outDir)

print("Generated AppIcon.icns at \(outIcns)")
