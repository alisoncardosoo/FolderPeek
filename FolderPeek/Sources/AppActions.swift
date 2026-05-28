import AppKit
import Foundation
import SwiftUI

enum FullDiskAccessState: Equatable {
    case granted
    case missing
    case unknown

    var title: String {
        switch self {
        case .granted:
            "Acesso Total ao Disco ativo"
        case .missing:
            "Acesso Total ao Disco necessário"
        case .unknown:
            "Acesso Total ao Disco não verificado"
        }
    }

    var message: String {
        switch self {
        case .granted:
            "FolderPeek já consegue acessar áreas protegidas do macOS para mover arquivos com mais liberdade."
        case .missing:
            "Ative esta permissão para arrastar arquivos da bandeja para pastas protegidas ou fora dos locais comuns."
        case .unknown:
            "Abra os Ajustes do Sistema e ative FolderPeek em Privacidade e Segurança."
        }
    }

    var icon: String {
        switch self {
        case .granted:
            "checkmark.shield.fill"
        case .missing:
            "lock.shield.fill"
        case .unknown:
            "questionmark.shield.fill"
        }
    }

    var color: Color {
        switch self {
        case .granted: .green
        case .missing: .red
        case .unknown: .red
        }
    }

    /// true quando a permissão foi confirmada como concedida
    var isGranted: Bool { self == .granted }
}

enum AppActions {
    static func revealAppInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

    static func openQuickLookExtensionsSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.ExtensionsPreferences") {
            NSWorkspace.shared.open(url)
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
        }
    }

    static func openFullDiskAccessSettings() {
        let preferenceURLs = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles"
        ]

        for urlString in preferenceURLs {
            if let url = URL(string: urlString), NSWorkspace.shared.open(url) {
                return
            }
        }

        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
    }

    static func fullDiskAccessState() -> FullDiskAccessState {
        var sawProtectedLocation = false

        for url in protectedFullDiskAccessProbeURLs() {
            let path = url.path(percentEncoded: false)
            // fileExists retorna true mesmo para diretórios sem permissão de leitura
            guard FileManager.default.fileExists(atPath: path) else { continue }
            sawProtectedLocation = true
            if canReadDirectory(at: url) {
                return .granted
            }
        }

        // Se ao menos uma pasta protegida existe mas não pôde ser lida → .missing (vermelho)
        // Se nenhuma pasta de probe encontrada (Mac incomum) → trata como .missing também
        return sawProtectedLocation ? .missing : .missing
    }

    static func appLocationText() -> String {
        Bundle.main.bundleURL.path(percentEncoded: false)
    }

    private static func protectedFullDiskAccessProbeURLs() -> [URL] {
        guard let libraryURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first else {
            return []
        }

        // Pastas que requerem FDA — ordenadas da mais comum à menos comum
        return [
            libraryURL.appendingPathComponent("Safari", isDirectory: true),
            libraryURL
                .appendingPathComponent("Application Support", isDirectory: true)
                .appendingPathComponent("com.apple.TCC", isDirectory: true),
            libraryURL.appendingPathComponent("Mail", isDirectory: true),
            libraryURL.appendingPathComponent("Messages", isDirectory: true),
            libraryURL.appendingPathComponent("Cookies", isDirectory: true),
            libraryURL.appendingPathComponent("HomeKit", isDirectory: true),
        ]
    }

    // MARK: - Launch permission prompt

    /// Chave UserDefaults que armazena o build em que o alerta foi dispensado.
    static let fdaPromptDismissedBuildKey = "fdaPromptDismissedForBuild"

    /// Exibe alerta de FDA se não concedido e o usuário não o dispensou neste build.
    @MainActor
    static func checkAndPromptForFullDiskAccessIfNeeded() {
        guard fullDiskAccessState() != .granted else { return }

        let currentBuild = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        let dismissedBuild = UserDefaults.standard.string(forKey: fdaPromptDismissedBuildKey) ?? ""
        guard dismissedBuild != currentBuild else { return }

        let alert = NSAlert()
        alert.messageText = "Acesso Total ao Disco necessário"
        alert.informativeText = """
            O FolderPeek precisa desta permissão para mover arquivos da bandeja para qualquer pasta do seu Mac sem prompts repetidos.

            Vá em Ajustes do Sistema › Privacidade e Segurança › Acesso Total ao Disco, ative o FolderPeek e clique em "Reiniciar FolderPeek".
            """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Abrir Ajustes")     // .alertFirstButtonReturn
        alert.addButton(withTitle: "Reiniciar agora")   // .alertSecondButtonReturn
        alert.addButton(withTitle: "Mais tarde")        // .alertThirdButtonReturn

        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            openFullDiskAccessSettings()
        case .alertSecondButtonReturn:
            relaunch()
        default:
            // "Mais tarde" — guarda build atual; reaparece na próxima instalação
            UserDefaults.standard.set(currentBuild, forKey: fdaPromptDismissedBuildKey)
        }
    }

    // MARK: - Relaunch

    /// Fecha o app atual e reabre uma nova instância via /usr/bin/open -n.
    static func relaunch() {
        let bundlePath = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-n", bundlePath]
        try? task.run()
        NSApp.terminate(nil)
    }

    private static func canReadDirectory(at url: URL) -> Bool {
        do {
            _ = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            return true
        } catch {
            return false
        }
    }
}
