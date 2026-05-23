import Foundation

public struct ArchiveScanner: Sendable {
    public init() {}

    public func scan(url: URL, preferences: PreviewPreferences = .default) throws -> PreviewResult {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "zip":
            return try ZipDirectoryReader().scan(url: url, preferences: preferences)
        case "tar", "tgz", "gz", "7z", "rar":
            throw PreviewScanError.unsupportedArchive(ext)
        default:
            throw PreviewScanError.unsupportedArchive(ext.isEmpty ? "arquivo" : ext)
        }
    }
}

private struct ZipDirectoryReader {
    private struct Entry {
        let name: String
        let compressedSize: UInt32
        let uncompressedSize: UInt32
        let modificationDate: Date?
        let isDirectory: Bool
    }

    func scan(url: URL, preferences: PreviewPreferences) throws -> PreviewResult {
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        let entries = try readEntries(from: data)
            .filter { preferences.showHiddenFiles || !$0.name.split(separator: "/").contains { $0.hasPrefix(".") } }

        let reachedLimit = entries.count > preferences.itemLimit
        let items = entries.prefix(preferences.itemLimit).map { entry in
            let displayName = entry.name.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let finalName = displayName.split(separator: "/").last.map(String.init) ?? displayName
            return PreviewItem(
                id: entry.name,
                name: finalName.isEmpty ? entry.name : finalName,
                kind: entry.isDirectory ? "Pasta" : archiveKind(for: entry.name),
                byteSize: entry.isDirectory ? nil : Int64(entry.uncompressedSize),
                modifiedAt: entry.modificationDate,
                relativePath: entry.name,
                isDirectory: entry.isDirectory,
                source: .archiveEntry(entry.name)
            )
        }

        let sorted = FolderScanner().sort(Array(items), foldersFirst: preferences.foldersFirst)
        let subtitle = "ZIP, \(FolderPeekFormatters.itemCountString(entries.count, reachedLimit: reachedLimit))"
        let warnings = reachedLimit ? ["Mostrando os primeiros \(preferences.itemLimit) itens do arquivo ZIP."] : []
        return PreviewResult(title: url.lastPathComponent, subtitle: subtitle, items: sorted, warnings: warnings, reachedLimit: reachedLimit)
    }

    private func readEntries(from data: Data) throws -> [Entry] {
        guard let eocdOffset = findEndOfCentralDirectory(in: data) else {
            throw PreviewScanError.invalidZip
        }

        let directorySize = Int(data.uint32(at: eocdOffset + 12))
        let directoryOffset = Int(data.uint32(at: eocdOffset + 16))
        guard directoryOffset >= 0, directorySize >= 0, directoryOffset + directorySize <= data.count else {
            throw PreviewScanError.invalidZip
        }

        var entries: [Entry] = []
        var cursor = directoryOffset
        while cursor + 46 <= directoryOffset + directorySize {
            guard data.uint32(at: cursor) == 0x02014b50 else { break }
            let modifiedTime = data.uint16(at: cursor + 12)
            let modifiedDate = data.uint16(at: cursor + 14)
            let compressedSize = data.uint32(at: cursor + 20)
            let uncompressedSize = data.uint32(at: cursor + 24)
            let fileNameLength = Int(data.uint16(at: cursor + 28))
            let extraLength = Int(data.uint16(at: cursor + 30))
            let commentLength = Int(data.uint16(at: cursor + 32))
            let nameStart = cursor + 46
            let nameEnd = nameStart + fileNameLength
            guard nameEnd <= data.count else { throw PreviewScanError.invalidZip }
            let nameData = data[nameStart..<nameEnd]
            let name = String(data: nameData, encoding: .utf8) ?? String(data: nameData, encoding: .isoLatin1) ?? "Arquivo"
            entries.append(Entry(
                name: name,
                compressedSize: compressedSize,
                uncompressedSize: uncompressedSize,
                modificationDate: dosDate(time: modifiedTime, date: modifiedDate),
                isDirectory: name.hasSuffix("/")
            ))
            cursor = nameEnd + extraLength + commentLength
        }
        return entries
    }

    private func findEndOfCentralDirectory(in data: Data) -> Int? {
        guard data.count >= 22 else { return nil }
        let minOffset = max(0, data.count - 65_557)
        var cursor = data.count - 22
        while cursor >= minOffset {
            if data.uint32(at: cursor) == 0x06054b50 { return cursor }
            cursor -= 1
        }
        return nil
    }

    private func archiveKind(for path: String) -> String {
        let url = URL(fileURLWithPath: path)
        return FileKindDetector.kind(for: url, isDirectory: false)
    }

    private func dosDate(time: UInt16, date: UInt16) -> Date? {
        let day = Int(date & 0x1F)
        let month = Int((date >> 5) & 0x0F)
        let year = Int((date >> 9) + 1980)
        let second = Int(time & 0x1F) * 2
        let minute = Int((time >> 5) & 0x3F)
        let hour = Int((time >> 11) & 0x1F)
        guard day > 0, month > 0 else { return nil }
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        return components.date
    }
}

private extension Data {
    func uint16(at offset: Int) -> UInt16 {
        UInt16(self[offset]) | (UInt16(self[offset + 1]) << 8)
    }

    func uint32(at offset: Int) -> UInt32 {
        UInt32(self[offset]) |
            (UInt32(self[offset + 1]) << 8) |
            (UInt32(self[offset + 2]) << 16) |
            (UInt32(self[offset + 3]) << 24)
    }
}
