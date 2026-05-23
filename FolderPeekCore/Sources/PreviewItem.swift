import Foundation

public struct PreviewItem: Identifiable, Equatable, Sendable {
    public enum Source: Equatable, Sendable {
        case fileSystem(URL)
        case archiveEntry(String)
    }

    public let id: String
    public let name: String
    public let kind: String
    public let byteSize: Int64?
    public let modifiedAt: Date?
    public let relativePath: String
    public let isDirectory: Bool
    public let source: Source
    public let depth: Int

    public init(
        id: String,
        name: String,
        kind: String,
        byteSize: Int64?,
        modifiedAt: Date?,
        relativePath: String,
        isDirectory: Bool,
        source: Source,
        depth: Int = 0
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.byteSize = byteSize
        self.modifiedAt = modifiedAt
        self.relativePath = relativePath
        self.isDirectory = isDirectory
        self.source = source
        self.depth = depth
    }
}

public struct PreviewResult: Equatable, Sendable {
    public let title: String
    public let subtitle: String
    public let items: [PreviewItem]
    public let warnings: [String]
    public let reachedLimit: Bool
    public let sourceURL: URL?

    public init(
        title: String,
        subtitle: String,
        items: [PreviewItem],
        warnings: [String] = [],
        reachedLimit: Bool = false,
        sourceURL: URL? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.items = items
        self.warnings = warnings
        self.reachedLimit = reachedLimit
        self.sourceURL = sourceURL
    }
}

public enum PreviewScanError: LocalizedError, Equatable, Sendable {
    case unsupportedArchive(String)
    case unreadable(URL)
    case invalidZip

    public var errorDescription: String? {
        switch self {
        case .unsupportedArchive(let ext):
            return "Ainda nao foi possivel listar arquivos .\(ext)."
        case .unreadable(let url):
            return "Nao foi possivel ler \(url.lastPathComponent)."
        case .invalidZip:
            return "O arquivo ZIP parece estar corrompido ou incompleto."
        }
    }
}
