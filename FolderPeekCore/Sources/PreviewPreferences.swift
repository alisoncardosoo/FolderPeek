import Foundation

public struct PreviewPreferences: Codable, Equatable, Sendable {
    public var fontSize: Double
    public var appearanceMode: PreviewAppearanceMode
    public var showHiddenFiles: Bool
    public var foldersFirst: Bool
    public var itemLimit: Int
    public var visibleColumns: Set<PreviewColumn>

    public init(
        fontSize: Double = 13,
        appearanceMode: PreviewAppearanceMode = .system,
        showHiddenFiles: Bool = false,
        foldersFirst: Bool = true,
        itemLimit: Int = 500,
        visibleColumns: Set<PreviewColumn> = Set(PreviewColumn.allCases)
    ) {
        self.fontSize = fontSize
        self.appearanceMode = appearanceMode
        self.showHiddenFiles = showHiddenFiles
        self.foldersFirst = foldersFirst
        self.itemLimit = max(25, min(itemLimit, 5_000))
        self.visibleColumns = visibleColumns
    }

    public static let `default` = PreviewPreferences()
}

public enum PreviewAppearanceMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .system: return "Seguir sistema"
        case .light: return "Sempre claro"
        case .dark: return "Sempre escuro"
        }
    }

    public var description: String {
        switch self {
        case .system: return "usa claro ou escuro conforme os Ajustes do macOS"
        case .light: return "mantem o app e o Quick Look no tema claro"
        case .dark: return "mantem o app e o Quick Look no tema escuro"
        }
    }

    public init(storedValue: String) {
        self = PreviewAppearanceMode(rawValue: storedValue) ?? .system
    }
}

public enum PreviewColumn: String, Codable, CaseIterable, Identifiable, Sendable {
    case icon
    case name
    case kind
    case size
    case modified
    case relativePath

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .icon: return ""
        case .name: return "Nome"
        case .kind: return "Tipo"
        case .size: return "Tamanho"
        case .modified: return "Modificado"
        case .relativePath: return "Caminho"
        }
    }
}
