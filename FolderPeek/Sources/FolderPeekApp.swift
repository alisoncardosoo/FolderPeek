import SwiftUI
import AppKit
import CoreGraphics
import FolderPeekCore
import UserNotifications

fileprivate let transferTrayWindowIdentifier = NSUserInterfaceItemIdentifier("folderpeek.transferTrayWindow")
fileprivate let transferTrayWindowDefaultSize = NSSize(width: 520, height: 320)
fileprivate let transferTrayWindowGap: CGFloat = 0

extension Notification.Name {
    static let folderPeekOpenMainWindow = Notification.Name("FolderPeekOpenMainWindow")
    static let folderPeekOpenTransferTray = Notification.Name("FolderPeekOpenTransferTray")
    static let folderPeekToggleTransferTray = Notification.Name("FolderPeekToggleTransferTray")
    static let folderPeekIngestTransferTrayURLs = Notification.Name("FolderPeekIngestTransferTrayURLs")
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
        NSApp.setActivationPolicy(.regular)

        let nc = NotificationCenter.default
        nc.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in
                self.syncDockPolicy()
            }
        }
        nc.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.syncDockPolicy() }
        }

        applyDockIcon()
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.applyDockIcon()
            }
        }

        hotKeyMonitor = GlobalHotKeyMonitor {
            NotificationCenter.default.post(name: .folderPeekToggleTransferTray, object: nil)
        }
        hotKeyMonitor?.start()

        finderDragMonitor = FinderDragMonitor { urls in
            guard !urls.isEmpty else { return }
            let autoShow = UserDefaults.standard.object(forKey: "autoShowOnDrag") as? Bool ?? true
            guard autoShow else { return }
            // Only show the tray as a drop target; files are added only when dropped into the tray.
            NotificationCenter.default.post(name: .folderPeekOpenTransferTray, object: nil)
        }
        finderDragMonitor?.start()

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeyMonitor?.stop()
        finderDragMonitor?.stop()
    }

    private func syncDockPolicy() {
        let hasVisibleRegularWindow = NSApp.windows.contains {
            $0.isVisible && ($0.level == .normal || $0.identifier == transferTrayWindowIdentifier)
        }
        NSApp.setActivationPolicy(hasVisibleRegularWindow ? .regular : .accessory)

        if hasVisibleRegularWindow {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                self.applyDockIcon()
            }
        }
    }

    private func applyDockIcon() {
        let style = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") ?? ""
        let isDark = style.lowercased().contains("dark")
        if isDark, let icon = scaledAppIcon(named: "AppIconDark", size: NSSize(width: 1024, height: 1024)) {
            NSApp.applicationIconImage = icon
        } else {
            NSApp.applicationIconImage = nil
        }
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
    @StateObject private var updaterController = UpdaterController()
    @StateObject private var transferTrayStore = TransferTrayStore()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        Window("Folder Peek", id: "main") {
            ContentView(updaterController: updaterController)
                .preferredColorScheme(PreviewAppearanceMode(storedValue: appearanceMode).colorScheme)
                .onReceive(NotificationCenter.default.publisher(for: .folderPeekOpenMainWindow)) { _ in
                    openMainWindow()
                }
                .onReceive(NotificationCenter.default.publisher(for: .folderPeekOpenTransferTray)) { _ in
                    openTransferTray(positionNearCursor: true)
                }
                .onReceive(NotificationCenter.default.publisher(for: .folderPeekToggleTransferTray)) { _ in
                    toggleTransferTray()
                }
                .onReceive(NotificationCenter.default.publisher(for: .folderPeekIngestTransferTrayURLs)) { notification in
                    ingestURLs(from: notification)
                }
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 512, height: 912)

        Window("Bandeja Temporária", id: "transferTray") {
            TransferTrayWindowView(
                store: transferTrayStore,
                hideWindow: closeTransferTray,
                configureWindow: configureTransferTrayWindow
            )
            .preferredColorScheme(PreviewAppearanceMode(storedValue: appearanceMode).colorScheme)
            .onReceive(NotificationCenter.default.publisher(for: .folderPeekIngestTransferTrayURLs)) { notification in
                ingestURLs(from: notification)
            }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: transferTrayWindowDefaultSize.width, height: transferTrayWindowDefaultSize.height)

        MenuBarExtra {
            MenuBarContent(
                updaterController: updaterController,
                openMainWindow: openMainWindow,
                openTransferTray: { openTransferTray(positionNearCursor: true) }
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
            .onReceive(NotificationCenter.default.publisher(for: .folderPeekOpenTransferTray)) { _ in
                openTransferTray(positionNearCursor: true)
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
                .onReceive(NotificationCenter.default.publisher(for: .folderPeekOpenTransferTray)) { _ in
                    openTransferTray(positionNearCursor: true)
                }
                .onReceive(NotificationCenter.default.publisher(for: .folderPeekToggleTransferTray)) { _ in
                    toggleTransferTray()
                }
                .onReceive(NotificationCenter.default.publisher(for: .folderPeekIngestTransferTrayURLs)) { notification in
                    ingestURLs(from: notification)
                }
        }
    }

    private static var menuBarIcon: NSImage? {
        scaledAppIcon(named: "FolderPeekMenuBarIcon", size: NSSize(width: 18, height: 18))
    }

    private func openMainWindow() {
        openWindow(id: "main")
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func openTransferTray(positionNearCursor: Bool) {
        openWindow(id: "transferTray")
        NSApp.setActivationPolicy(.regular)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            guard let trayWindow = findTransferTrayWindow() else {
                return
            }
            closeExtraTransferTrayWindows(keeping: trayWindow)
            configureTransferTrayWindow(trayWindow)
            if positionNearCursor {
                positionTransferTrayWindow(trayWindow)
            }
            trayWindow.makeKeyAndOrderFront(nil)
        }
    }

    private func closeTransferTray() {
        transferTrayStore.restorePendingItemsToOriginBeforeClosingTray()
        for trayWindow in transferTrayWindows() {
            trayWindow.close()
        }
    }

    private func toggleTransferTray() {
        if let trayWindow = findTransferTrayWindow(), trayWindow.isVisible {
            closeTransferTray()
            return
        }
        openTransferTray(positionNearCursor: true)
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
        window.minSize = NSSize(width: 300, height: 220)
        window.maxSize = NSSize(width: 900, height: 700)
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

        let savedW = UserDefaults.standard.double(forKey: "shelfWindowWidth")
        let savedH = UserDefaults.standard.double(forKey: "shelfWindowHeight")
        if savedW >= 300, savedH >= 220 {
            window.setContentSize(NSSize(
                width: min(savedW, 900),
                height: min(savedH, 700)
            ))
        }

        NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: window,
            queue: .main
        ) { [weak window] _ in
            guard let window else { return }
            MainActor.assumeIsolated {
                UserDefaults.standard.set(window.frame.width, forKey: "shelfWindowWidth")
                UserDefaults.standard.set(window.frame.height, forKey: "shelfWindowHeight")
            }
        }

    }

    private func findTransferTrayWindow() -> NSWindow? {
        transferTrayWindows().first
    }

    private func positionTransferTrayWindow(_ window: NSWindow) {
        let windowSize = window.frame.size.width > 0
            ? window.frame.size
            : transferTrayWindowDefaultSize

        if let finderFrame = frontmostFinderWindowFrame() {
            positionTray(window, nextTo: finderFrame, windowSize: windowSize)
            return
        }

        let pointer = NSEvent.mouseLocation
        var targetOrigin = NSPoint(
            x: pointer.x + 12,
            y: pointer.y - (windowSize.height / 2)
        )
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(pointer, $0.frame, false) }) {
            targetOrigin = clampedOrigin(targetOrigin, windowSize: windowSize, in: screen.visibleFrame)
        }
        window.setFrame(NSRect(origin: targetOrigin, size: windowSize), display: true)
    }

    private func transferTrayWindows() -> [NSWindow] {
        NSApp.windows.filter { $0.identifier == transferTrayWindowIdentifier }
    }

    private func closeExtraTransferTrayWindows(keeping primaryWindow: NSWindow) {
        for window in transferTrayWindows() where window !== primaryWindow {
            window.close()
        }
    }

    private func positionTray(_ window: NSWindow, nextTo finderFrame: NSRect, windowSize: NSSize) {
        var origin = NSPoint(
            x: finderFrame.maxX + transferTrayWindowGap,
            y: finderFrame.midY - (windowSize.height / 2)
        )

        let screen = NSScreen.screens.first(where: { $0.visibleFrame.intersects(finderFrame) }) ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            if origin.x + windowSize.width > visible.maxX {
                origin.x = finderFrame.minX - windowSize.width - transferTrayWindowGap
            }
            origin = clampedOrigin(origin, windowSize: windowSize, in: visible)
        }

        window.setFrame(NSRect(origin: origin, size: windowSize), display: true)
    }

    private func clampedOrigin(_ origin: NSPoint, windowSize: NSSize, in visibleFrame: NSRect) -> NSPoint {
        let minX = visibleFrame.minX + 8
        let maxX = visibleFrame.maxX - windowSize.width - 8
        let minY = visibleFrame.minY + 8
        let maxY = visibleFrame.maxY - windowSize.height - 8

        return NSPoint(
            x: max(minX, min(maxX, origin.x)),
            y: max(minY, min(maxY, origin.y))
        )
    }

    private func frontmostFinderWindowFrame() -> NSRect? {
        guard let rawWindows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        let mainScreenHeight = NSScreen.screens.first(where: { $0.frame.origin == .zero })?.frame.height ?? NSScreen.main?.frame.height ?? 0

        for windowInfo in rawWindows {
            guard let ownerName = windowInfo[kCGWindowOwnerName as String] as? String,
                  ownerName == "Finder",
                  let layer = windowInfo[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  let bounds = windowInfo[kCGWindowBounds as String] as? [String: Any] else {
                continue
            }

            guard let cgRect = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  cgRect.width > 160,
                  cgRect.height > 120 else {
                continue
            }

            let appKitY = mainScreenHeight - cgRect.origin.y - cgRect.height
            return NSRect(x: cgRect.origin.x, y: appKitY, width: cgRect.width, height: cgRect.height)
        }

        return nil
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
