import AppKit
import SwiftUI

@main
enum BrisaMain {
    static func main() {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--screenshot"), i + 1 < args.count {
            _ = NSApplication.shared
            MainActor.assumeIsolated { Screenshot.render(to: URL(fileURLWithPath: args[i + 1])) }
            return
        }
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
            Self.logRedirect(url)
            Task {
                await store.linkLegacy(redirect: url)
                showPopover()
            }
        }
    }

    /// Records redirects with secrets masked, to debug LG's sign-in flow.
    private static func logRedirect(_ url: URL) {
        var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let items = parts?.queryItems
        parts?.queryItems = items?.map { item in
            ["code", "access_token", "refresh_token", "token"].contains(item.name)
                ? URLQueryItem(name: item.name, value: "<\(item.value?.count ?? 0) chars>") : item
        }
        Log.write(parts?.string ?? url.scheme ?? "")
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
        updateTitle()
    }

    /// Opening Brisa again (Spotlight, Dock, Finder) while it runs brings the item back with the panel.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        statusItem.isVisible = true
        DispatchQueue.main.async { self.showPopover() }
        return false
    }

    private func updateTitle() {
        guard let button = statusItem?.button else { return }
        // Only show while the AC runs; keep it during setup, errors, or while the panel is open.
        let needsAttention = !store.hasToken || !store.isConnected
        statusItem.isVisible = store.isOn || needsAttention || popover.isShown
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

/// Appends a line to ~/Library/Logs/Brisa.log.
enum Log {
    static func write(_ message: String) {
        let line = "\(Date()) \(message)\n"
        let log = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Logs/Brisa.log")
        if let handle = try? FileHandle(forWritingTo: log) {
            handle.seekToEndOfFile(); handle.write(Data(line.utf8)); try? handle.close()
        } else {
            try? Data(line.utf8).write(to: log)
        }
    }
}
