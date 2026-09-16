// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

//
// Draws the jitpass mark (a dot inside a soft ring, jitpass.com/icon.svg) on
// the macOS rounded-square icon shape, at every size an .iconset needs.
//   swift scripts/icon.swift <out-dir>
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
let green = NSColor(srgbRed: 0x3E / 255, green: 0xCF / 255, blue: 0x8E / 255, alpha: 1)
let plate = NSColor(srgbRed: 0x1C / 255, green: 0x1F / 255, blue: 0x2B / 255, alpha: 1)

func render(_ px: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)
    // Apple's icon grid: the plate fills ~80% of the canvas, corners ~22%.
    let inset = s * 0.10
    let plateRect = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    plate.setFill()
    NSBezierPath(roundedRect: plateRect, xRadius: plateRect.width * 0.2237, yRadius: plateRect.width * 0.2237).fill()
    let c = NSPoint(x: s / 2, y: s / 2)
    let ring = plateRect.width * 0.36
    green.withAlphaComponent(0.22).setFill()
    NSBezierPath(ovalIn: NSRect(x: c.x - ring, y: c.y - ring, width: ring * 2, height: ring * 2)).fill()
    let dot = ring * 9 / 16
    green.setFill()
    NSBezierPath(ovalIn: NSRect(x: c.x - dot, y: c.y - dot, width: dot * 2, height: dot * 2)).fill()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128), ("128x128@2x", 256),
                   ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)]
{
    let data = render(px).representation(using: .png, properties: [:])!
    try! data.write(to: out.appendingPathComponent("icon_\(name).png"))
}

print("wrote iconset to \(out.path)")
