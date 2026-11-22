// Draws the app icon PNG. Run: ./make_icon.sh
import AppKit

let size: CGFloat = 1024
let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()

// macOS icon grid: 824pt rounded square centered on a 1024 canvas
let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
let path = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
NSShadow().apply { $0.shadowBlurRadius = 20; $0.shadowOffset = NSSize(width: 0, height: -10); $0.shadowColor = .black.withAlphaComponent(0.3) }
NSGradient(starting: NSColor(red: 0.16, green: 0.18, blue: 0.24, alpha: 1),
           ending: NSColor(red: 0.06, green: 0.07, blue: 0.10, alpha: 1))!.draw(in: path, angle: -90)
NSShadow().set()

// A mini Dock: two app tiles, a divider line, two app tiles.
let bar = NSRect(x: 160, y: 400, width: 704, height: 224)
NSColor.white.withAlphaComponent(0.10).setFill()
NSBezierPath(roundedRect: bar, xRadius: 70, yRadius: 70).fill()

let colors: [NSColor] = [
    NSColor(red: 0.25, green: 0.55, blue: 1.00, alpha: 1), NSColor(red: 0.20, green: 0.80, blue: 0.45, alpha: 1),
    NSColor(red: 1.00, green: 0.55, blue: 0.25, alpha: 1), NSColor(red: 0.95, green: 0.30, blue: 0.45, alpha: 1),
]
let xs: [CGFloat] = [196, 336, 548, 688]
for (x, c) in zip(xs, colors) {
    c.setFill()
    NSBezierPath(roundedRect: NSRect(x: x, y: 452, width: 120, height: 120), xRadius: 30, yRadius: 30).fill()
}
NSColor.white.withAlphaComponent(0.85).setFill()
NSBezierPath(roundedRect: NSRect(x: 503, y: 442, width: 18, height: 140), xRadius: 9, yRadius: 9).fill()

img.unlockFocus()

let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))

extension NSShadow { func apply(_ f: (NSShadow) -> Void) { f(self); set() } }
