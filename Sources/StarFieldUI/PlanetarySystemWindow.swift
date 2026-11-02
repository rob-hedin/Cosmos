#if os(macOS)
import AppKit
import StarCatalog
import SwiftUI

/// Opens Planetary System windows from AppKit code, or from the star view's info card.
@MainActor
public enum PlanetarySystemWindow {
    /// Shows `system` in a window titled with its name, or with `title` if given. If a window for
    /// an equal system is already open, it is brought to the front instead of opening another, and
    /// `title` is ignored. Returns the window. The window releases itself when closed.
    @discardableResult
    public static func open(system: PlanetarySystem, title: String? = nil) -> NSWindow {
        if let existing = openWindows[system]?.window {
            if existing.isMiniaturized { existing.deminiaturize(nil) }
            existing.makeKeyAndOrderFront(nil)
            return existing
        }
        let content = PlanetarySystemView(system: system)
            .frame(minWidth: 480, minHeight: 360)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1_000, height: 750),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = title ?? system.name
        window.contentView = NSHostingView(rootView: content)
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        let id = ObjectIdentifier(window)
        let closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { _ in
            MainActor.assumeIsolated { windowWillClose(id) }
        }
        openWindows[system] = OpenWindow(id: id, window: window, closeObserver: closeObserver)
        return window
    }

    private struct OpenWindow {
        let id: ObjectIdentifier
        let window: NSWindow
        let closeObserver: any NSObjectProtocol
    }

    /// Keeps windows alive while they are open, and finds the one showing a system.
    private static var openWindows: [PlanetarySystem: OpenWindow] = [:]

    private static func windowWillClose(_ id: ObjectIdentifier) {
        guard let system = openWindows.first(where: { $0.value.id == id })?.key,
              let closed = openWindows.removeValue(forKey: system)
        else { return }
        NotificationCenter.default.removeObserver(closed.closeObserver)
    }
}
#endif
