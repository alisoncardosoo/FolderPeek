import Compression
import Foundation

// MARK: - Public API

public struct ArchiveScanner: Sendable {
    public init() {}

    public func scan(url: URL, preferences: PreviewPreferences = .default) throws -> PreviewResult {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "zip":
            return try ZipDirectoryReader().scan(url: url, preferences: preferences)

        case "tar":
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            return try TarDirectoryReader().scan(
                data: data, title: url.lastPathComponent,
                format: "TAR", preferences: preferences)

        case "tgz":
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            let decompressed = try GzipDecompressor.decompress(data)
            return try TarDirectoryReader().scan(
                data: decompressed, title: url.lastPathComponent,
                format: "TGZ", preferences: preferences)

        case "gz":
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            // Resolve inner name: from gzip FNAME header, or strip extension
            let innerName = GzipDecompressor.originalFilename(data)
                ?? url.deletingPathExtension().lastPathComponent
            if innerName.hasSuffix(".tar") {
                // .tar.gz case
                let decompressed = try GzipDecompressor.decompress(data)
                return try TarDirectoryReader().scan(
                    data: decompressed, title: url.lastPathComponent,
                    format: "TAR.GZ", preferences: preferences)
            } else {
                // Plain .gz wrapping a single file
                return gzSingleFileResult(url: url, innerName: innerName, data: data)
            }

        case "7z":
            throw PreviewScanError.unsupportedArchive("7z")

        case "rar":
            throw PreviewScanError.unsupportedArchive("rar")

        default:
            throw PreviewScanError.unsupportedArchive(ext.isEmpty ? "arquivo" : ext)
        }
    }

    private func gzSingleFileResult(url: URL, innerName: String, data: Data) -> PreviewResult {
        let size = GzipDecompressor.uncompressedSize(data)
        let item = PreviewItem(
            id: innerName,
            name: innerName,
            kind: FileKindDetector.kind(for: URL(fileURLWithPath: innerName), isDirectory: false),
            byteSize: size,
            modifiedAt: nil,
            relativePath: innerName,
            isDirectory: false,
            source: .archiveEntry(innerName)
        )
        return PreviewResult(title: url.lastPathComponent, subtitle: "GZ · 1 item", items: [item])
    }
}

// MARK: - TAR Reader

private struct TarDirectoryReader {

    private struct Entry {
        let name: String
        let size: Int64
        let modifiedAt: Date?
        let isDirectory: Bool
    }

    func scan(data: Data, title: String, format: String, preferences: PreviewPreferences) throws -> PreviewResult {
        var entries = readEntries(from: data)
        if !preferences.showHiddenFiles {
            entries = entries.filter { entry in
                !entry.name.split(separator: "/").contains(where: { $0.hasPrefix(".") })
            }
        }

        let reachedLimit = entries.count > preferences.itemLimit
        let items: [PreviewItem] = entries.prefix(preferences.itemLimit).map { entry in
            let parts = entry.name.split(separator: "/")
            let displayName = parts.last.map(String.init) ?? entry.name
            return PreviewItem(
                id: entry.name,
                name: displayName.isEmpty ? entry.name : displayName,
                kind: entry.isDirectory
                    ? "Pasta"
                    : FileKindDetector.kind(for: URL(fileURLWithPath: entry.name), isDirectory: false),
                byteSize: entry.isDirectory ? nil : entry.size,
                modifiedAt: entry.modifiedAt,
                relativePath: entry.name,
                isDirectory: entry.isDirectory,
                source: .archiveEntry(entry.name)
            )
        }

        let sorted = FolderScanner().sort(items, foldersFirst: preferences.foldersFirst)
        let subtitle = "\(format) · \(FolderPeekFormatters.itemCountString(entries.count, reachedLimit: reachedLimit))"
        let warnings = reachedLimit ? ["Mostrando os primeiros \(preferences.itemLimit) itens."] : []
        return PreviewResult(
            title: title, subtitle: subtitle,
            items: sorted, warnings: warnings,
            reachedLimit: reachedLimit
        )
    }

    // MARK: TAR header parser (POSIX ustar + GNU extensions)

    private func readEntries(from data: Data) -> [Entry] {
        var entries: [Entry] = []
        var offset = 0
        var pendingLongName: String? = nil
        var seen = Set<String>()

        while offset + 512 <= data.count {
            // Null block = end of archive
            var isNull = true
            for i in 0..<512 where data[offset + i] != 0 { isNull = false; break }
            if isNull { break }

            // Standard TAR header fields (offsets relative to block start)
            let name     = field(data, base: offset, off: 0,   len: 100)
            let sizeStr  = field(data, base: offset, off: 124, len: 12)
            let mtimeStr = field(data, base: offset, off: 136, len: 12)
            let typeFlag = data[offset + 156]
            let prefix   = field(data, base: offset, off: 345, len: 155)  // ustar prefix

            // File size: GNU base-256 (high bit set) or standard octal string
            let rawSize: Int64
            if data[offset + 124] & 0x80 != 0 {
                var v: Int64 = 0
                for i in 1..<12 { v = (v << 8) | Int64(data[offset + 124 + i]) }
                rawSize = v
            } else {
                rawSize = Int64(sizeStr, radix: 8) ?? 0
            }

            let mtime = Int64(mtimeStr, radix: 8)
                .map { Date(timeIntervalSince1970: TimeInterval($0)) }
            let skip = rawSize > 0 ? (Int(rawSize) + 511) / 512 : 0

            // Normalise type flag: null byte → '0' (regular file)
            let flag: UInt8 = typeFlag == 0 ? 48 : typeFlag

            switch flag {
            case 76:  // 'L' – GNU long filename; actual name is in the next data block
                let end = min(offset + 512 + Int(rawSize), data.count)
                if offset + 512 < end {
                    let d = data[(offset + 512)..<end]
                    pendingLongName = String(data: d, encoding: .utf8)?
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
                }

            case 75:        // 'K' – GNU long linkname, not needed
                pendingLongName = nil

            case 120, 103:  // 'x', 'g' – PAX extended headers, skip
                pendingLongName = nil

            case 53:  // '5' – directory
                let full = buildName(pending: &pendingLongName, name: name, prefix: prefix)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                if !full.isEmpty, !seen.contains(full) {
                    seen.insert(full)
                    entries.append(Entry(name: full, size: 0, modifiedAt: mtime, isDirectory: true))
                }

            default:  // '0', '7', '\0' – regular file; symlinks shown as files
                let full = buildName(pending: &pendingLongName, name: name, prefix: prefix)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                if !full.isEmpty, !seen.contains(full) {
                    seen.insert(full)
                    entries.append(Entry(name: full, size: rawSize, modifiedAt: mtime, isDirectory: false))
                }
            }

            offset += 512 + (skip * 512)
        }

        return entries
    }

    private func buildName(pending: inout String?, name: String, prefix: String) -> String {
        defer { pending = nil }
        if let p = pending { return p }
        return prefix.isEmpty ? name : "\(prefix)/\(name)"
    }

    /// Reads a null-terminated ASCII/UTF-8 field from a TAR block.
    private func field(_ data: Data, base: Int, off: Int, len: Int) -> String {
        var bytes = [UInt8]()
        let start = base + off
        let end   = min(start + len, data.count)
        for i in start..<end {
            if data[i] == 0 { break }
            bytes.append(data[i])
        }
        return String(bytes: bytes, encoding: .utf8)
            ?? String(bytes: bytes, encoding: .isoLatin1)
            ?? ""
    }
}

// MARK: - Gzip Decompressor

/// Decompresses gzip streams using Apple's Compression framework.
///
/// Apple's `COMPRESSION_ZLIB` algorithm decodes raw DEFLATE (RFC 1951),
/// which is exactly the payload inside a gzip container (RFC 1952).
/// We strip the gzip header/trailer and feed the raw DEFLATE bytes to the decoder.
private enum GzipDecompressor {

    enum GzipError: LocalizedError {
        case notGzip, tooSmall, initFailed, decompressFailed
        var errorDescription: String? {
            switch self {
            case .notGzip:          return "Não é um arquivo GZIP válido."
            case .tooSmall:         return "Arquivo GZIP incompleto."
            case .initFailed:       return "Falha ao inicializar o descompressor."
            case .decompressFailed: return "Falha ao descompactar o arquivo."
            }
        }
    }

    /// Returns the original filename stored in the gzip FNAME field, if present.
    static func originalFilename(_ data: Data) -> String? {
        guard data.count >= 10, data[0] == 0x1f, data[1] == 0x8b else { return nil }
        var off = 10
        let flags = data[3]
        if flags & 0x04 != 0 {
            guard off + 2 <= data.count else { return nil }
            let xlen = Int(data[off]) | Int(data[off + 1]) << 8
            off += 2 + xlen
        }
        guard flags & 0x08 != 0 else { return nil }
        var bytes = [UInt8]()
        while off < data.count && data[off] != 0 { bytes.append(data[off]); off += 1 }
        return String(bytes: bytes, encoding: .utf8)
    }

    /// Reads the ISIZE field (last 4 bytes): uncompressed size mod 2³².
    static func uncompressedSize(_ data: Data) -> Int64? {
        guard data.count >= 8 else { return nil }
        let o = data.count - 4
        let v = Int64(data[o])
              | Int64(data[o + 1]) << 8
              | Int64(data[o + 2]) << 16
              | Int64(data[o + 3]) << 24
        return v > 0 ? v : nil
    }

    /// Decompresses a full gzip stream into memory using `compression_decode_buffer`.
    ///
    /// Uses the ISIZE field as an initial capacity hint and retries with a larger
    /// buffer if the first attempt fails — handles archives where ISIZE is unreliable.
    static func decompress(_ data: Data) throws -> Data {
        guard data.count >= 18, data[0] == 0x1f, data[1] == 0x8b else {
            throw GzipError.notGzip
        }
        let deflateStart = try headerEnd(data)
        let deflateEnd   = data.count - 8   // skip CRC32 (4) + ISIZE (4)
        guard deflateEnd > deflateStart else { throw GzipError.tooSmall }

        // ISIZE = uncompressed size mod 2^32 (0 means unknown / wraps around)
        let isizeOff = data.count - 4
        let isize = Int(data[isizeOff])
                  | Int(data[isizeOff + 1]) << 8
                  | Int(data[isizeOff + 2]) << 16
                  | Int(data[isizeOff + 3]) << 24

        // Cap at 500 MB so Quick Look stays responsive
        let maxCapacity = 500 * 1024 * 1024
        let srcCount    = deflateEnd - deflateStart
        var capacity    = isize > 0 && isize <= maxCapacity
                          ? isize
                          : min(srcCount * 4, maxCapacity)
        capacity = max(capacity, 65_536)

        // Retry with a progressively larger buffer if the estimate is too small
        for attempt in 0..<5 {
            var buf = [UInt8](repeating: 0, count: capacity)
            let written = buf.withUnsafeMutableBufferPointer { dst in
                data.withUnsafeBytes { src in
                    compression_decode_buffer(
                        dst.baseAddress!,
                        capacity,
                        src.baseAddress!.advanced(by: deflateStart)
                            .assumingMemoryBound(to: UInt8.self),
                        srcCount,
                        nil,
                        COMPRESSION_ZLIB
                    )
                }
            }
            if written > 0 { return Data(buf.prefix(written)) }
            guard attempt < 4, capacity < maxCapacity else { break }
            capacity = min(capacity * 4, maxCapacity)
        }
        throw GzipError.decompressFailed
    }

    /// Byte offset where the raw DEFLATE payload begins (after the gzip header).
    private static func headerEnd(_ data: Data) throws -> Int {
        var off = 10
        let flags = data[3]
        if flags & 0x04 != 0 {
            guard off + 2 <= data.count else { throw GzipError.tooSmall }
            let xlen = Int(data[off]) | Int(data[off + 1]) << 8
            off += 2 + xlen
        }
        if flags & 0x08 != 0 { while off < data.count && data[off] != 0 { off += 1 }; off += 1 }
        if flags & 0x10 != 0 { while off < data.count && data[off] != 0 { off += 1 }; off += 1 }
        if flags & 0x02 != 0 { off += 2 }
        guard off < data.count else { throw GzipError.tooSmall }
        return off
    }
}

// MARK: - ZIP Reader

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
        let subtitle = "ZIP · \(FolderPeekFormatters.itemCountString(entries.count, reachedLimit: reachedLimit))"
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
            let modifiedTime    = data.uint16(at: cursor + 12)
            let modifiedDate    = data.uint16(at: cursor + 14)
            let compressedSize  = data.uint32(at: cursor + 20)
            let uncompressedSize = data.uint32(at: cursor + 24)
            let fileNameLength  = Int(data.uint16(at: cursor + 28))
            let extraLength     = Int(data.uint16(at: cursor + 30))
            let commentLength   = Int(data.uint16(at: cursor + 32))
            let nameStart = cursor + 46
            let nameEnd   = nameStart + fileNameLength
            guard nameEnd <= data.count else { throw PreviewScanError.invalidZip }
            let nameData = data[nameStart..<nameEnd]
            let name = String(data: nameData, encoding: .utf8)
                ?? String(data: nameData, encoding: .isoLatin1)
                ?? "Arquivo"
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
        FileKindDetector.kind(for: URL(fileURLWithPath: path), isDirectory: false)
    }

    private func dosDate(time: UInt16, date: UInt16) -> Date? {
        let day    = Int(date & 0x1F)
        let month  = Int((date >> 5) & 0x0F)
        let year   = Int((date >> 9) + 1980)
        let second = Int(time & 0x1F) * 2
        let minute = Int((time >> 5) & 0x3F)
        let hour   = Int((time >> 11) & 0x1F)
        guard day > 0, month > 0 else { return nil }
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.year = year; components.month = month; components.day = day
        components.hour = hour; components.minute = minute; components.second = second
        return components.date
    }
}

private extension Data {
    func uint16(at offset: Int) -> UInt16 {
        UInt16(self[offset]) | (UInt16(self[offset + 1]) << 8)
    }
    func uint32(at offset: Int) -> UInt32 {
        UInt32(self[offset])
            | (UInt32(self[offset + 1]) << 8)
            | (UInt32(self[offset + 2]) << 16)
            | (UInt32(self[offset + 3]) << 24)
    }
}
