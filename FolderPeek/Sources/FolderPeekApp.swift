import SwiftUI
import AppKit
import CoreGraphics
import FolderPeekCore
import UserNotifications

fileprivate let transferTrayWindowIdentifier = NSUserInterfaceItemIdentifier("folderpeek.transferTrayWindow")
fileprivate let transferTrayInitialSize = TransferTrayLayout(itemCount: 0).windowSize

extension Notification.Name {
    static let folderPeekOpenMainWindow = Notification.Name("FolderPeekOpenMainWindow")
    static let folderPeekOpenTransferTray = Notification.Name("FolderPeekOpenTransferTray")
    static let folderPeekToggleTransferTray = Notification.Name("FolderPeekToggleTransferTray")
    static let folderPeekIngestTransferTrayURLs = Notification.Name("FolderPeekIngestTransferTrayURLs")
    static let folderPeekDragEndedOutsideTray = Notification.Name("FolderPeekDragEndedOutsideTray")
}

fileprivate func scaledAppIcon(named name: String, size: NSSize) -> NSImage? {
    guard let image = NSImage(named: name), let copy = image.copy() as? NSImage else {
        return nil
    }

    copy.size = size
    return copy
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var finderDragMonitor: FinderDragMonitor?
    private var hotKeyMonitor: GlobalHotKeyMonitor?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
        NSApp.setActivationPolicy(.accessory)

        hotKeyMonitor = GlobalHotKeyMonitor {
            NotificationCenter.default.post(name: .folderPeekToggleTransferTray, object: nil)
        }
        hotKeyMonitor?.start()

        finderDragMonitor = FinderDragMonitor(
            onFilesDetected: { urls, exitPoint in
                guard !urls.isEmpty else { return }
                let autoShow = UserDefaults.standard.object(forKey: "autoShowOnDrag") as? Bool ?? true
                guard autoShow else { return }
                // Only show the tray as a drop target; files are added only when dropped into the tray.
                NotificationCenter.default.post(name: .folderPeekOpenTransferTray, object: NSValue(point: exitPoint))
            },
            onDragEnded: {
                // Drag released: if nothing was dropped into the tray, hide the empty drop target.
                NotificationCenter.default.post(name: .folderPeekDragEndedOutsideTray, object: nil)
            }
        )
        finderDragMonitor?.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeyMonitor?.stop()
        finderDragMonitor?.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        false
    }
}

@MainActor
final class TransferTrayWindowDelegate: NSObject, NSWindowDelegate {
    static let shared = TransferTrayWindowDelegate()

    var shouldAutoHide: (() -> Bool)?
    var hideAction: (() -> Void)?
    var beforeCloseAction: (() -> Void)?

    func windowDidResignKey(_ notification: Notification) {
        guard shouldAutoHide?() == true else {
            return
        }
        hideAction?()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        beforeCloseAction?()
        return true
    }
}

@main
struct FolderPeekApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @AppStorage("appearanceMode") private var appearanceMode = PreviewAppearanceMode.system.rawValue
    @AppStorage("transferTrayPosition") private var transferTrayPosition = TransferTrayPosition.topRight.rawValue
    @StateObject private var updaterController = UpdaterController()
    @StateObject private var transferTrayStore = TransferTrayStore()
    @State private var mainWindow: NSWindow?
    @State private var trayWindow: NSWindow?

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(
                updaterController: updaterController,
                openMainWindow: openMainWindow,
                openTransferTray: { openTransferTray() }
            )
        } label: {
            HStack(spacing: 3) {
                if let icon = Self.menuBarIcon {
                    Image(nsImage: icon)
                }
                if !transferTrayStore.items.isEmpty {
                    Text("\(transferTrayStore.items.count)")
                        .font(.system(size: 10, weight: .semibold))
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .folderPeekOpenMainWindow)) { _ in
                openMainWindow()
            }
            .onReceive(NotificationCenter.default.publisher(for: .folderPeekDragEndedOutsideTray)) { _ in
                hideTrayIfEmpty()
            }
            .onReceive(NotificationCenter.default.publisher(for: .folderPeekOpenTransferTray)) { notification in
                openTransferTray(at: (notification.object as? NSValue)?.pointValue)
            }
            .onChange(of: transferTrayPosition) { _, _ in
                guard let window = findTransferTrayWindow(), window.isVisible else { return }
                positionTransferTrayWindow(window, on: window.screen)
            }
            .onReceive(NotificationCenter.default.publisher(for: .folderPeekToggleTransferTray)) { _ in
                toggleTransferTray()
            }
            .onReceive(NotificationCenter.default.publisher(for: .folderPeekIngestTransferTrayURLs)) { notification in
                ingestURLs(from: notification)
            }
        }

        Settings {
            PreferencesView(updaterController: updaterController)
                .preferredColorScheme(PreviewAppearanceMode(storedValue: appearanceMode).colorScheme)
        }
    }

    private static var menuBarIcon: NSImage? {
        scaledAppIcon(named: "FolderPeekMenuBarIcon", size: NSSize(width: 18, height: 18))
    }

    // Create windows only on demand so launch and relaunch stay in the menu bar on macOS 14+.
    private func openMainWindow() {
        let window: NSWindow
        if let existingWindow = mainWindow {
            window = existingWindow
        } else {
            window = NSWindow(
                contentRect: NSRect(origin: .zero, size: mainWindowDefaultContentSize),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Folder Peek"
            window.isReleasedWhenClosed = false
            window.isRestorable = false
            let hostingController = NSHostingController(rootView:
                AppWindowContent {
                    ContentView(updaterController: updaterController)
                }
            )
            // AppKit owns the opening size; SwiftUI only supplies the resize minimum.
            hostingController.sizingOptions = [.minSize]
            window.contentViewController = hostingController
            window.setContentSize(mainWindowDefaultContentSize)
            window.center()
            mainWindow = window
        }
        if let screen = window.screen ?? NSScreen.main {
            window.setFrame(
                mainWindowFrame(window.frame, fitting: screen.visibleFrame.insetBy(dx: 12, dy: 12)),
                display: false
            )
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            guard window.isVisible else { return }
            AppActions.checkAndPromptForFullDiskAccessIfNeeded()
        }
    }

    private func openTransferTray(at exitPoint: NSPoint? = nil) {
        let window: NSWindow
        if let existingWindow = trayWindow {
            window = existingWindow
        } else {
            window = NSWindow(
                contentRect: NSRect(origin: .zero, size: transferTrayInitialSize),
                styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.contentViewController = NSHostingController(rootView:
                AppWindowContent {
                    TransferTrayWindowView(
                        store: transferTrayStore,
                        hideWindow: closeTransferTray,
                        configureWindow: configureTransferTrayWindow,
                        resizeWindow: resizeTrayWindow
                    )
                }
            )
            trayWindow = window
        }
        configureTransferTrayWindow(window)
        positionTransferTrayWindow(window, at: exitPoint)
        if exitPoint != nil {
            // Keep Finder as the active drag source while exposing the drop target.
            window.orderFrontRegardless()
        } else {
            window.makeKeyAndOrderFront(nil)
        }
    }

    private func closeTransferTray() {
        guard transferTrayStore.pendingDropCount == 0 else { return }
        transferTrayStore.restorePendingItemsToOriginBeforeClosingTray()
        for trayWindow in transferTrayWindows() {
            trayWindow.close()
        }
    }

    private func hideTrayIfEmpty() {
        // Defer so a drop landing on the tray has time to ingest its files before we check emptiness.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            guard let trayWindow = findTransferTrayWindow(), trayWindow.isVisible else { return }
            guard transferTrayStore.items.isEmpty, !transferTrayStore.isProcessing,
                  transferTrayStore.pendingDropCount == 0 else { return }
            closeTransferTray()
        }
    }

    private func toggleTransferTray() {
        if let trayWindow = findTransferTrayWindow(), trayWindow.isVisible {
            closeTransferTray()
            return
        }
        openTransferTray()
    }

    private func ingestURLs(from notification: Notification) {
        guard let urls = notification.object as? [URL], !urls.isEmpty else {
            return
        }
        transferTrayStore.addFiles(urls)
    }

    private func configureTransferTrayWindow(_ window: NSWindow) {
        // Only do one-time setup when the window isn't yet identified; always refresh delegates.
        let alreadyConfigured = window.identifier == transferTrayWindowIdentifier
        TransferTrayWindowDelegate.shared.shouldAutoHide = {
            transferTrayStore.items.isEmpty && !transferTrayStore.isProcessing
                && transferTrayStore.pendingDropCount == 0
        }
        TransferTrayWindowDelegate.shared.hideAction = { closeTransferTray() }
        TransferTrayWindowDelegate.shared.beforeCloseAction = {
            transferTrayStore.restorePendingItemsToOriginBeforeClosingTray()
        }
        window.delegate = TransferTrayWindowDelegate.shared
        guard !alreadyConfigured else { return }

        window.identifier = transferTrayWindowIdentifier
        window.title = "Bandeja Temporária"
        window.level = .floating
        window.tabbingMode = .disallowed
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.minSize = trayWindowSize(for: 0)
        window.maxSize = trayWindowSize(for: 9)
        window.styleMask.insert(.resizable)
        window.styleMask.remove(.miniaturizable)
        window.collectionBehavior.insert(.canJoinAllSpaces)
        window.collectionBehavior.insert(.fullScreenAuxiliary)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.hasShadow = false
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true

        let initialSize = trayWindowSize(for: transferTrayStore.items.count)
        window.setContentSize(initialSize)

    }

    private func findTransferTrayWindow() -> NSWindow? {
        transferTrayWindows().first
    }

    private func positionTransferTrayWindow(
        _ window: NSWindow, at exitPoint: NSPoint? = nil, on screen: NSScreen? = nil
    ) {
        let pointer = exitPoint ?? NSEvent.mouseLocation
        guard let targetScreen = screen
            ?? NSScreen.screens.first(where: { NSMouseInRect(pointer, $0.frame, false) })
            ?? NSScreen.main else { return }
        let frame = TransferTrayPosition(storedValue: transferTrayPosition).frame(
            windowSize: trayWindowSize(for: transferTrayStore.items.count),
            in: targetScreen.visibleFrame
        )
        window.setFrame(frame, display: true)
    }

    private func trayWindowSize(for itemCount: Int) -> NSSize {
        TransferTrayViewMode.saved.windowSize(itemCount: itemCount)
    }

    private func resizeTrayWindow(to itemCount: Int) {
        guard let window = findTransferTrayWindow(), window.isVisible else { return }
        window.minSize = trayWindowSize(for: 0)
        window.maxSize = trayWindowSize(for: 9)
        let newSize = trayWindowSize(for: itemCount)
        guard window.frame.size != newSize else { return }
        guard let screen = window.screen ?? NSScreen.main else { return }
        let frame = TransferTrayPosition(storedValue: transferTrayPosition).frame(
            windowSize: newSize, in: screen.visibleFrame
        )
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().setFrame(frame, display: true)
        }
    }

    private func transferTrayWindows() -> [NSWindow] {
        NSApp.windows.filter { $0.identifier == transferTrayWindowIdentifier }
    }


}

// Each hosted window observes appearance changes independently of the menu bar scene.
private struct AppWindowContent<Content: View>: View {
    @AppStorage("appearanceMode") private var appearanceMode = PreviewAppearanceMode.system.rawValue
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .preferredColorScheme(PreviewAppearanceMode(storedValue: appearanceMode).colorScheme)
    }
}

private extension PreviewAppearanceMode {
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

private struct MenuBarContent: View {
    @Environment(\.openSettings) private var openSettings
    let updaterController: UpdaterController
    let openMainWindow: () -> Void
    let openTransferTray: () -> Void

    var body: some View {
        Button("Abrir Folder Peek") {
            openMainWindow()
        }

        Button("Abrir bandeja temporária") {
            openTransferTray()
        }

        Button("Mostrar app no Finder") {
            AppActions.revealAppInFinder()
        }

        Button("Abrir Ajustes de Extensoes") {
            AppActions.openQuickLookExtensionsSettings()
        }

        Button("Abrir Acesso Total ao Disco") {
            AppActions.openFullDiskAccessSettings()
        }

        Divider()

        Button("Verificar atualizacoes…") {
            updaterController.checkForUpdates()
            NSApp.activate(ignoringOtherApps: true)
        }

        Divider()

        Button("Preferencias") {
            openSettings()
            NSApp.activate(ignoringOtherApps: true)
        }

        Divider()

        Button("Sair") {
            NSApp.terminate(nil)
        }
    }
}
