import SwiftUI
import AppKit
import CoreGraphics
import FolderPeekCore
import UserNotifications

fileprivate let transferTrayWindowIdentifier = NSUserInterfaceItemIdentifier("folderpeek.transferTrayWindow")
// Initial window size for 2-column × 2-row grid: (14+2)×2 horiz pad + 2×100 tiles + 10 spacing = 242w
// Height: 78px fixed (header + padding) + 82px per row × 2 rows = 242h
fileprivate let transferTrayInitialSize = NSSize(width: 242, height: 242)

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

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }

        // Aguarda a janela principal aparecer antes de exibir o alerta de FDA
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            AppActions.checkAndPromptForFullDiskAccessIfNeeded()
        }
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
                .onReceive(NotificationCenter.default.publisher(for: .folderPeekOpenTransferTray)) { notification in
                    openTransferTray(at: (notification.object as? NSValue)?.pointValue)
                }
                .onReceive(NotificationCenter.default.publisher(for: .folderPeekToggleTransferTray)) { _ in
                    toggleTransferTray()
                }
                .onReceive(NotificationCenter.default.publisher(for: .folderPeekIngestTransferTrayURLs)) { notification in
                    ingestURLs(from: notification)
                }
                .onReceive(NotificationCenter.default.publisher(for: .folderPeekDragEndedOutsideTray)) { _ in
                    hideTrayIfEmpty()
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
            .onChange(of: transferTrayStore.items.count) { _, count in
                resizeTrayWindow(to: count)
            }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: transferTrayInitialSize.width, height: transferTrayInitialSize.height)

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
            .onReceive(NotificationCenter.default.publisher(for: .folderPeekOpenTransferTray)) { notification in
                openTransferTray(at: (notification.object as? NSValue)?.pointValue)
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
                .onReceive(NotificationCenter.default.publisher(for: .folderPeekOpenTransferTray)) { notification in
                    openTransferTray(at: (notification.object as? NSValue)?.pointValue)
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

    private func openTransferTray(at exitPoint: NSPoint? = nil) {
        openWindow(id: "transferTray")
        NSApp.setActivationPolicy(.regular)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            guard let trayWindow = findTransferTrayWindow() else { return }
            closeExtraTransferTrayWindows(keeping: trayWindow)
            configureTransferTrayWindow(trayWindow)
            positionTransferTrayWindow(trayWindow, at: exitPoint)
            trayWindow.makeKeyAndOrderFront(nil)
        }
    }

    private func closeTransferTray() {
        transferTrayStore.restorePendingItemsToOriginBeforeClosingTray()
        for trayWindow in transferTrayWindows() {
            trayWindow.close()
        }
    }

    private func hideTrayIfEmpty() {
        // Defer so a drop landing on the tray has time to ingest its files before we check emptiness.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            guard let trayWindow = findTransferTrayWindow(), trayWindow.isVisible else { return }
            guard transferTrayStore.items.isEmpty, !transferTrayStore.isProcessing else { return }
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
        window.minSize = NSSize(width: 220, height: 200)
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

        let initialSize = trayWindowSize(for: transferTrayStore.items.count)
        window.setContentSize(initialSize)

    }

    private func findTransferTrayWindow() -> NSWindow? {
        transferTrayWindows().first
    }

    private func positionTransferTrayWindow(_ window: NSWindow, at exitPoint: NSPoint? = nil) {
        let windowSize = trayWindowSize(for: transferTrayStore.items.count)
        let pointer = exitPoint ?? NSEvent.mouseLocation
        var targetOrigin = NSPoint(
            x: pointer.x,
            y: pointer.y - windowSize.height / 2
        )
        let screen = NSScreen.screens.first(where: { NSMouseInRect(pointer, $0.frame, false) }) ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            targetOrigin = clampedOrigin(targetOrigin, windowSize: windowSize, in: visible)
        }
        window.setFrame(NSRect(origin: targetOrigin, size: windowSize), display: true)
    }

    private func trayWindowSize(for itemCount: Int, windowWidth: CGFloat = 242) -> NSSize {
        // Grid layout constants (from TransferTrayWindowView):
        // tile cell h = 58 image + 6+6 padding = 70; row spacing = 12; grid v-pad = 8
        // fixed overhead (header + padding) ≈ 78px; per-row cost = 82px (70 cell + 12 spacing, last row no spacing → amortized)
        let cols = max(1, Int((windowWidth - 22) / 98))  // adaptive: floor((w-22)/98)
        let rows = max(2, min(5, Int(ceil(Double(max(1, itemCount)) / Double(cols)))))
        let height: CGFloat = 78 + 82 * CGFloat(rows)
        return NSSize(width: windowWidth, height: height)
    }

    private func resizeTrayWindow(to itemCount: Int) {
        guard let window = findTransferTrayWindow(), window.isVisible else { return }
        let newSize = trayWindowSize(for: itemCount, windowWidth: window.frame.width)
        guard abs(newSize.height - window.frame.height) > 4 else { return }
        var frame = window.frame
        frame.origin.y -= newSize.height - frame.height  // grow upward
        frame.size.height = newSize.height
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().setFrame(frame, display: true)
        }
    }

    private func transferTrayWindows() -> [NSWindow] {
        NSApp.windows.filter { $0.identifier == transferTrayWindowIdentifier }
    }

    private func closeExtraTransferTrayWindows(keeping primaryWindow: NSWindow) {
        for window in transferTrayWindows() where window !== primaryWindow {
            window.close()
        }
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
