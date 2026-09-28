// Renders the 1024×1024 App Store icon (brand gradient + white leaf). Run: swift scripts/make_app_icon.swift <out.png>
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments.dropFirst().first ?? "AppIcon.png"
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(size),
    pixelsHigh: Int(size),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let rect = NSRect(x: 0, y: 0, width: size, height: size)
NSGradient(colors: [NSColor(red: 0.13, green: 0.70, blue: 0.40, alpha: 1), NSColor(red: 0.03, green: 0.38, blue: 0.20, alpha: 1)])!
    .draw(in: rect, angle: -60)
// Soft highlight
NSColor.white.withAlphaComponent(0.08).setFill()
NSBezierPath(ovalIn: NSRect(x: -200, y: 520, width: 900, height: 700)).fill()
let config = NSImage.SymbolConfiguration(pointSize: 560, weight: .semibold).applying(.init(paletteColors: [.white]))
let leaf = NSImage(systemSymbolName: "leaf.fill", accessibilityDescription: nil)!.withSymbolConfiguration(config)!
let leafSize = leaf.size
leaf.draw(in: NSRect(x: (size - leafSize.width) / 2, y: (size - leafSize.height) / 2 - 10, width: leafSize.width, height: leafSize.height))
NSGraphicsContext.restoreGraphicsState()
// Written with alpha; `make icon` flattens it to opaque RGB (App Store requirement) with sips.
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
