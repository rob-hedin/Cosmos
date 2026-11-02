import SwiftUI

/// A ready-made scene showing the star field. Use it in an `App`'s body on macOS or iOS:
///
/// ```swift
/// @main struct MyApp: App {
///     var body: some Scene { StarFieldScene() }
/// }
/// ```
public struct StarFieldScene: Scene {
    private let title: String
    private let focus: StarFieldFocus?
    private let route: [String]
    private let filter: StarFilter

    /// Opens on `focus` if given, otherwise frames `route`, showing the stars `filter` lets
    /// through; see ``StarFieldView``.
    public init(title: String = "Stars", focus: StarFieldFocus? = nil, route: [String] = [], filter: StarFilter = .all) {
        self.title = title
        self.focus = focus
        self.route = route
        self.filter = filter
    }

    public var body: some Scene {
        #if os(macOS)
        WindowGroup(title) {
            StarFieldBrowser(focus: focus, route: route, filter: filter)
                .frame(minWidth: 480, minHeight: 360)
        }
        .defaultSize(width: 1_000, height: 750)
        #else
        WindowGroup(title) {
            StarFieldBrowser(focus: focus, route: route, filter: filter)
        }
        #endif
    }
}

#if os(macOS)
import AppKit

/// Opens and manages a star field window from AppKit code, without a SwiftUI `App`.
@MainActor
public enum StarFieldWindow {
    /// Opens a new window showing the catalog and returns it. Pass `focus` to open centered on a
    /// star at a span in light years, or `route` to draw and frame a list of stars. The window releases itself when closed.
    @discardableResult
    public static func open(
        catalog: StarCatalog? = nil,
        sizeMode: StarSizeMode = .luminosity,
        title: String = "Stars",
        focus: StarFieldFocus? = nil,
        route: [String] = [],
        filter: StarFilter = .all
    ) -> NSWindow {
        let content = catalog.map {
            StarFieldView(catalog: $0, sizeMode: sizeMode, focus: focus, route: route, filter: filter)
        } ?? StarFieldView(sizeMode: sizeMode, focus: focus, route: route, filter: filter)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1_000, height: 750),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
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
        openWindows[id] = OpenWindow(window: window, closeObserver: closeObserver)
        return window
    }

    private struct OpenWindow {
        let window: NSWindow
        let closeObserver: any NSObjectProtocol
    }

    /// Keeps windows alive while they are open.
    private static var openWindows: [ObjectIdentifier: OpenWindow] = [:]

    private static func windowWillClose(_ id: ObjectIdentifier) {
        guard let closed = openWindows.removeValue(forKey: id) else { return }
        NotificationCenter.default.removeObserver(closed.closeObserver)
    }
}
#endif
