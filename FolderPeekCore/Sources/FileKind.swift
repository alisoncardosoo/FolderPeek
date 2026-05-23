import Foundation
import UniformTypeIdentifiers

public enum FileKindDetector {
    public static func kind(for url: URL, isDirectory: Bool) -> String {
        if isDirectory { return "Pasta" }
        let ext = url.pathExtension
        guard !ext.isEmpty else { return "Arquivo" }
        if let type = UTType(filenameExtension: ext) {
            return type.localizedDescription ?? ext.uppercased()
        }
        return ext.uppercased()
    }

    public static func isSupportedArchive(_ url: URL) -> Bool {
        supportedArchiveExtensions.contains(url.pathExtension.lowercased())
    }

    public static let supportedArchiveExtensions: Set<String> = ["zip", "tar", "tgz", "gz", "7z", "rar"]
}
