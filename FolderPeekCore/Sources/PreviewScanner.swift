import Foundation

public struct PreviewScanner: Sendable {
    public init() {}

    public func scan(url: URL, preferences: PreviewPreferences = .default) throws -> PreviewResult {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
        if values?.isDirectory == true {
            return try FolderScanner().scan(url: url, preferences: preferences)
        }
        if FileKindDetector.isSupportedArchive(url) {
            return try ArchiveScanner().scan(url: url, preferences: preferences)
        }
        throw PreviewScanError.unreadable(url)
    }
}
