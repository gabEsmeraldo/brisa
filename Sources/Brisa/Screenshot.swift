import AppKit
import SwiftUI

/// `Brisa --screenshot <dir>` renders the panels with sample data for the README.
@MainActor
enum Screenshot {
    static func render(to dir: URL) {
        Theme.forceFlat = true
        let store = ACStore()
        store.token = "sample"
        store.isConnected = true
        store.isOn = true
        store.mode = "COOL"
        store.fan = "HIGH"
        store.currentTemp = 24
        store.targetTemp = 18
        store.jet = true
        store.legacyLinked = true
        store.caps.hasJet = true
        store.caps.hasEco = true
        store.caps.hasSleep = true
        store.caps.hasSwingVertical = true
        store.caps.minC = 18
        store.caps.maxC = 30
        store.devices = [ACDevice(id: "1", name: "Bedroom")]
        store.deviceID = "1"

        snap(PopoverView(store: store), to: dir.appending(path: "panel.png"))
        snap(SettingsView(store: store, close: {}).padding(18).frame(width: 430).background(Color.black)
            .preferredColorScheme(.dark), to: dir.appending(path: "settings.png"))
    }

    private static func snap<V: View>(_ view: V, to url: URL) {
        let host = NSHostingView(rootView: view)
        host.appearance = NSAppearance(named: .darkAqua)
        host.frame.size = host.fittingSize
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        window.layoutIfNeeded()
        host.layoutSubtreeIfNeeded()
        let scale: CGFloat = 2
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(host.bounds.width * scale),
                                   pixelsHigh: Int(host.bounds.height * scale), bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = host.bounds.size
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
