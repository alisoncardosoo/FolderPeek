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
        case .granted:
            .green
        case .missing:
            .orange
        case .unknown:
            .secondary
        }
    }
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
            guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
                continue
            }
            sawProtectedLocation = true
            if canReadDirectory(at: url) {
                return .granted
            }
        }

        return sawProtectedLocation ? .missing : .unknown
    }

    static func appLocationText() -> String {
        Bundle.main.bundleURL.path(percentEncoded: false)
    }

    private static func protectedFullDiskAccessProbeURLs() -> [URL] {
        guard let libraryURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first else {
            return []
        }

        return [
            libraryURL.appendingPathComponent("Safari", isDirectory: true),
            libraryURL.appendingPathComponent("Mail", isDirectory: true),
            libraryURL.appendingPathComponent("Messages", isDirectory: true),
            libraryURL
                .appendingPathComponent("Application Support", isDirectory: true)
                .appendingPathComponent("com.apple.TCC", isDirectory: true)
        ]
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
