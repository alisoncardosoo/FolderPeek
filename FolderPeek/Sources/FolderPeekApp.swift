import SwiftUI
import AppKit
import FolderPeekCore

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
    }

    private func syncDockPolicy() {
        let hasVisibleRegularWindow = NSApp.windows.contains {
            $0.isVisible && $0.level == .normal
        }
        NSApp.setActivationPolicy(hasVisibleRegularWindow ? .regular : .accessory)
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
            Image("FolderPeekMenuBarIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
        }

        Settings {
            PreferencesView()
                .preferredColorScheme(PreviewAppearanceMode(storedValue: appearanceMode).colorScheme)
        }
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
