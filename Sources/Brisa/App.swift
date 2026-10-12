import AppKit
import SwiftUI

@main
enum BrisaMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let store = ACStore()
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()

    private static let closedInterval: TimeInterval = 300
    private static let openInterval: TimeInterval = 60

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageLeading
        }

        popover.behavior = .transient
        popover.animates = true
        popover.appearance = NSAppearance(named: .darkAqua)
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: PopoverView(store: store))

        store.onChange = { [weak self] in self?.updateTitle() }
        updateTitle()
        store.startPolling(every: Self.closedInterval, refreshNow: true)

        // First run: open straight into Settings so the token can be pasted.
        if !store.hasToken {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.showPopover() }
        }
    }

    /// LG's sign-in redirect (`lgaccount.lgsmartthinq:/?code=…`) coming back from the browser.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == LegacyThinQ.redirectScheme {
            Task {
                await store.linkLegacy(redirect: url)
                showPopover()
            }
        }
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let isRightClick = event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true
        if isRightClick && store.hasToken && store.isConnected {
            popover.performClose(nil)
            store.setPower(!store.isOn)
            return
        }
        popover.isShown ? popover.performClose(nil) : showPopover()
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    func popoverDidShow(_ notification: Notification) {
        store.startPolling(every: Self.openInterval, refreshNow: true)
    }

    func popoverDidClose(_ notification: Notification) {
        store.startPolling(every: Self.closedInterval, refreshNow: false)
    }

    private func updateTitle() {
        guard let button = statusItem?.button else { return }
        let symbol = store.isConnected ? "snowflake" : "snowflake.slash"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Brisa")
        image?.isTemplate = true
        button.image = image
        if let t = store.currentTemp, store.isConnected {
            button.title = " \(Int(t.rounded()))°"
        } else {
            button.title = ""
        }
        // Dim the item while the unit is off.
        button.appearsDisabled = !(store.isConnected && store.isOn)
        button.toolTip = store.lastError ?? (store.isOn ? L("On") : L("Off"))
    }
}
