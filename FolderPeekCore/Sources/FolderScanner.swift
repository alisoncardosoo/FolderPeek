import Foundation

public struct FolderScanner {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func scan(url: URL, preferences: PreviewPreferences = .default) throws -> PreviewResult {
        guard url.hasDirectoryPath || (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
            throw PreviewScanError.unreadable(url)
        }

        let keys: Set<URLResourceKey> = [.isDirectoryKey, .contentModificationDateKey, .fileSizeKey, .isHiddenKey]

        guard let topChildren = try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: Array(keys), options: []) else {
            throw PreviewScanError.unreadable(url)
        }

        let visibleTop = topChildren.filter { isVisible($0, showHidden: preferences.showHiddenFiles) }
        let topLevelCount = visibleTop.count

        let topItems = sort(
            visibleTop.map { makeItem(url: $0, keys: keys, depth: 0) },
            foldersFirst: preferences.foldersFirst
        )

        var allItems: [PreviewItem] = []
        var reachedLimit = false

        for item in topItems {
            guard allItems.count < preferences.itemLimit else { reachedLimit = true; break }
            allItems.append(item)

            guard item.isDirectory, case .fileSystem(let dirURL) = item.source else { continue }
            let childURLs = (try? fileManager.contentsOfDirectory(
                at: dirURL, includingPropertiesForKeys: Array(keys), options: []
            )) ?? []
            let visibleChildren = sort(
                childURLs.filter { isVisible($0, showHidden: preferences.showHiddenFiles) }
                    .map { makeItem(url: $0, keys: keys, depth: 1) },
                foldersFirst: preferences.foldersFirst
            )
            for child in visibleChildren {
                guard allItems.count < preferences.itemLimit else { reachedLimit = true; break }
                allItems.append(child)
            }
        }

        let subtitle = FolderPeekFormatters.itemCountString(topLevelCount, reachedLimit: false)
        let warnings = reachedLimit ? ["Mostrando os primeiros \(preferences.itemLimit) itens para manter o Quick Look rapido."] : []
        return PreviewResult(
            title: url.lastPathComponent,
            subtitle: subtitle,
            items: allItems,
            warnings: warnings,
            reachedLimit: reachedLimit,
            sourceURL: url
        )
    }

    public func sort(_ items: [PreviewItem], foldersFirst: Bool) -> [PreviewItem] {
        items.sorted { lhs, rhs in
            if foldersFirst, lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory && !rhs.isDirectory
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private func isVisible(_ url: URL, showHidden: Bool) -> Bool {
        guard !showHidden else { return true }
        if url.lastPathComponent.hasPrefix(".") { return false }
        let values = try? url.resourceValues(forKeys: [.isHiddenKey])
        return values?.isHidden != true
    }

    private func makeItem(url: URL, keys: Set<URLResourceKey>, depth: Int) -> PreviewItem {
        let values = try? url.resourceValues(forKeys: keys)
        let isDirectory = values?.isDirectory == true
        return PreviewItem(
            id: url.path,
            name: url.lastPathComponent,
            kind: FileKindDetector.kind(for: url, isDirectory: isDirectory),
            byteSize: isDirectory ? nil : Int64(values?.fileSize ?? 0),
            modifiedAt: values?.contentModificationDate,
            relativePath: url.lastPathComponent,
            isDirectory: isDirectory,
            source: .fileSystem(url),
            depth: depth
        )
    }
}
