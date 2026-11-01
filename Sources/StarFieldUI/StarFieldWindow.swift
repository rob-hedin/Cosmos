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

    public init(title: String = "Stars") {
        self.title = title
    }

    public var body: some Scene {
        WindowGroup(title) {
            StarFieldView()
                .frame(minWidth: 480, minHeight: 360)
        }
        #if os(macOS)
        .defaultSize(width: 1_000, height: 750)
        #endif
    }
}

#if os(macOS)
import AppKit

/// Opens and manages a star field window from AppKit code, without a SwiftUI `App`.
@MainActor
public enum StarFieldWindow {
    /// Opens a new window showing the catalog and returns it. The window releases itself when closed.
    @discardableResult
    public static func open(
        catalog: StarCatalog? = nil,
        sizeMode: StarSizeMode = .luminosity,
        title: String = "Stars"
    ) -> NSWindow {
        let content = catalog.map { StarFieldView(catalog: $0, sizeMode: sizeMode) }
            ?? StarFieldView(sizeMode: sizeMode)
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
        openWindows.insert(window)
        _ = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { notification in
            guard let closed = notification.object as? NSWindow else { return }
            MainActor.assumeIsolated { _ = openWindows.remove(closed) }
        }
        return window
    }

    /// Keeps windows alive while they are open.
    private static var openWindows: Set<NSWindow> = []
}
#endif
