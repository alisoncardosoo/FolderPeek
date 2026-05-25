import SwiftUI
import AppKit
import FolderPeekCore

fileprivate func scaledAppIcon(named name: String, size: NSSize) -> NSImage? {
    guard let image = NSImage(named: name), let copy = image.copy() as? NSImage else {
        return nil
    }

    copy.size = size
    return copy
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let nc = NotificationCenter.default
        nc.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { _ in
            self.syncDockPolicy()
        }
        nc.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.syncDockPolicy() }
        }

        // Ícone do Dock: acompanha o modo claro/escuro do sistema
        applyDockIcon()
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.applyDockIcon()
        }
    }

    private func syncDockPolicy() {
        let hasVisibleRegularWindow = NSApp.windows.contains {
            $0.isVisible && $0.level == .normal
        }
        NSApp.setActivationPolicy(hasVisibleRegularWindow ? .regular : .accessory)
        // Re-aplica o ícone dark após cada troca de policy (o Dock reseta ao virar .regular)
        if hasVisibleRegularWindow {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                self.applyDockIcon()
            }
        }
    }

    private func applyDockIcon() {
        // AppIcon do bundle = versão CLARA (padrão, mostrada no Launchpad).
        // Em dark mode, troca dinamicamente o ícone do Dock para a versão escura.
        let style = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") ?? ""
        let isDark = style.lowercased().contains("dark")
        if isDark, let icon = scaledAppIcon(named: "AppIconDark", size: NSSize(width: 1024, height: 1024)) {
            NSApp.applicationIconImage = icon
        } else {
            NSApp.applicationIconImage = nil   // usa o AppIcon do bundle (claro)
        }
    }
}

@main
struct FolderPeekApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @AppStorage("appearanceMode") private var appearanceMode = PreviewAppearanceMode.system.rawValue

    var body: some Scene {
        WindowGroup("Folder Peek", id: "main") {
            ContentView()
                .preferredColorScheme(PreviewAppearanceMode(storedValue: appearanceMode).colorScheme)
        }
        .windowStyle(.titleBar)

        MenuBarExtra {
            MenuBarContent()
        } label: {
            if let icon = Self.menuBarIcon {
                Image(nsImage: icon)
            }
        }

        Settings {
            PreferencesView()
                .preferredColorScheme(PreviewAppearanceMode(storedValue: appearanceMode).colorScheme)
        }
    }

    private static var menuBarIcon: NSImage? {
        scaledAppIcon(named: "FolderPeekMenuBarIcon", size: NSSize(width: 18, height: 18))
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

// MARK: - Menu Bar

private struct MenuBarContent: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button("Abrir Folder Peek") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }

        Button("Mostrar app no Finder") {
            AppActions.revealAppInFinder()
        }

        Button("Abrir Ajustes de Extensoes") {
            AppActions.openQuickLookExtensionsSettings()
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
