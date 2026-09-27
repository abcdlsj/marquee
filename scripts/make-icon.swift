// Renders the 1024px app icon: a thin white Didot M on black.
// Usage: swift scripts/make-icon.swift Marquee/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png
import AppKit

let size = 1024.0
let out = CommandLine.arguments.dropFirst().first ?? "icon-1024.png"
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

ctx.setFillColor(CGColor(gray: 0.02, alpha: 1))
ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))

let para = NSMutableParagraphStyle(); para.alignment = .center
let font = NSFont(name: "Didot", size: 520) ?? NSFont(name: "Georgia", size: 480)!
let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor(white: 0.94, alpha: 1), .paragraphStyle: para]
let m = NSAttributedString(string: "M", attributes: attrs)
let b = m.boundingRect(with: CGSize(width: size, height: size), options: [.usesLineFragmentOrigin])
m.draw(in: CGRect(x: 0, y: (size - b.height) / 2 - 20, width: size, height: b.height))

NSGraphicsContext.current = nil
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
