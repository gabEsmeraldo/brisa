// Renders assets/dmg-background.svg into build/dmg-background.tiff (1x + 2x).
import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
guard let svg = NSImage(contentsOf: root.appending(path: "assets/dmg-background.svg")) else { fatalError("can't read svg") }
let out = root.appending(path: "build")
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
for scale in [1, 2] {
    let w = 660 * scale, h = 400 * scale
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: 660, height: 400)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    svg.draw(in: NSRect(x: 0, y: 0, width: 660, height: 400))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: out.appending(path: scale == 1 ? "bg.png" : "bg@2x.png"))
}
