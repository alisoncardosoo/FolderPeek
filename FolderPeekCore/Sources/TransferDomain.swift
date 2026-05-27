import Foundation

public enum TransferOperation: String, CaseIterable, Codable, Sendable {
    case copy
    case move
}

public enum TransferExecutionStatus: Equatable, Sendable {
    case success
    case failure(String)
}

public struct TransferExecutionResult: Equatable, Sendable {
    public let sourceURL: URL
    public let destinationURL: URL?
    public let status: TransferExecutionStatus

    public init(sourceURL: URL, destinationURL: URL?, status: TransferExecutionStatus) {
        self.sourceURL = sourceURL
        self.destinationURL = destinationURL
        self.status = status
    }
}

public struct TransferItemCollection: Sendable {
    public struct InsertResult: Equatable, Sendable {
        public let inserted: [URL]
        public let duplicates: [URL]
        public let skippedForLimit: [URL]

        public init(inserted: [URL], duplicates: [URL], skippedForLimit: [URL]) {
            self.inserted = inserted
            self.duplicates = duplicates
            self.skippedForLimit = skippedForLimit
        }
    }

    public let limit: Int
    public private(set) var items: [URL]
    private var canonicalPaths: Set<String>

    public init(limit: Int = 500, initialItems: [URL] = []) {
        self.limit = max(1, limit)
        self.items = []
        self.canonicalPaths = []
        _ = add(initialItems)
    }

    @discardableResult
    public mutating func add(_ urls: [URL]) -> InsertResult {
        var inserted: [URL] = []
        var duplicates: [URL] = []
        var skippedForLimit: [URL] = []

        for url in urls where url.isFileURL {
            guard items.count < limit else {
                skippedForLimit.append(url)
                continue
            }

            let canonicalPath = Self.canonicalPath(for: url)
            if canonicalPaths.contains(canonicalPath) {
                duplicates.append(url)
                continue
            }

            canonicalPaths.insert(canonicalPath)
            items.append(url)
            inserted.append(url)
        }

        return InsertResult(inserted: inserted, duplicates: duplicates, skippedForLimit: skippedForLimit)
    }

    public mutating func remove(_ url: URL) {
        let canonicalPath = Self.canonicalPath(for: url)
        items.removeAll { candidate in
            Self.canonicalPath(for: candidate) == canonicalPath
        }
        canonicalPaths.remove(canonicalPath)
    }

    public mutating func clear() {
        items.removeAll(keepingCapacity: true)
        canonicalPaths.removeAll(keepingCapacity: true)
    }

    public func contains(_ url: URL) -> Bool {
        canonicalPaths.contains(Self.canonicalPath(for: url))
    }

    public static func canonicalPath(for url: URL) -> String {
        let normalized = url.standardizedFileURL.resolvingSymlinksInPath()
        return normalized.path(percentEncoded: false)
    }
}
