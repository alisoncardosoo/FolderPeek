import AppKit
import Foundation
import FolderPeekCore
import Combine
import UserNotifications

@MainActor
final class TransferTrayStore: ObservableObject {
    enum ItemStatus: Equatable {
        case ready
        case success
        case failure(String)
    }

    struct Item: Identifiable {
        let id: String
        let url: URL
        let name: String
        let byteSize: Int64?
        let originalURL: URL?
        let shouldDeleteOnClose: Bool
        var status: ItemStatus
    }

    @Published private(set) var items: [Item] = []
    @Published var operation: TransferOperation = .copy
    @Published private(set) var destinationURL: URL?
    @Published var isProcessing = false
    @Published var statusMessage: String?
    @Published var showMoveConfirmation = false
    @Published var transferProgress: Double = 0
    @Published var currentTransferName: String = ""

    private var thumbnailCache: [URL: NSImage] = [:]
    private var thumbnailLoadingInProgress: Set<URL> = []
    private let destinationBookmarkKey = "transferTrayDestinationBookmark"
    private let legacyPendingItemsKey = "transferTrayPendingBookmarks"
    private let coordinator = FileTransferCoordinator()
    private var collection = TransferItemCollection(limit: 500)
    private var lastMoveMap: [(source: URL, destination: URL)] = []

    private struct StagedFileResult {
        let stagedURL: URL
        let originalURL: URL?
        let shouldDeleteOnClose: Bool
        let usedCopyThenDeleteFallback: Bool
    }

    init() {
        ensureTrayDirectoryExists()
        loadDestinationBookmark()
        loadPendingItems()
    }

    var destinationPathText: String {
        destinationURL?.path(percentEncoded: false) ?? "Nenhuma pasta selecionada"
    }

    var trayTitle: String {
        "Bandeja"
    }

    var canExecuteTransfer: Bool {
        !items.isEmpty && destinationURL != nil && !isProcessing
    }

    func thumbnail(for item: Item) -> NSImage {
        if let cached = thumbnailCache[item.url] {
            return cached
        }
        loadThumbnailIfNeeded(for: item.url)
        return NSWorkspace.shared.icon(forFile: item.url.path(percentEncoded: false))
    }

    func addFiles(_ urls: [URL]) {
        guard let trayDirectoryURL = ensureTrayDirectoryExists() else {
            statusMessage = "Não foi possível preparar a pasta da bandeja."
            return
        }

        var stagedURLs: [URL] = []
        var stagedMetadataByCanonicalPath: [String: (originalURL: URL?, shouldDeleteOnClose: Bool)] = [:]
        var failedCount = 0
        var fallbackMoveCount = 0

        for droppedURL in urls where droppedURL.isFileURL {
            let normalizedDroppedURL = normalizedFilePathURL(from: droppedURL)
            do {
                let staged = try stageFileIfNeeded(normalizedDroppedURL, trayDirectoryURL: trayDirectoryURL)
                let stagedCanonical = TransferItemCollection.canonicalPath(for: staged.stagedURL)
                stagedMetadataByCanonicalPath[stagedCanonical] = (
                    originalURL: staged.originalURL,
                    shouldDeleteOnClose: staged.shouldDeleteOnClose
                )
                if staged.usedCopyThenDeleteFallback {
                    fallbackMoveCount += 1
                }
                stagedURLs.append(staged.stagedURL)
            } catch {
                failedCount += 1
            }
        }

        let result = collection.add(stagedURLs)

        for stagedURL in result.inserted {
            let canonical = TransferItemCollection.canonicalPath(for: stagedURL)
            let metadata = stagedMetadataByCanonicalPath[canonical]
            items.append(
                Item(
                    id: canonical,
                    url: stagedURL,
                    name: stagedURL.lastPathComponent,
                    byteSize: fileSize(for: stagedURL),
                    originalURL: metadata?.originalURL,
                    shouldDeleteOnClose: metadata?.shouldDeleteOnClose ?? false,
                    status: .ready
                )
            )
            loadThumbnailIfNeeded(for: stagedURL)
        }

        var statusParts: [String] = []
        if !result.inserted.isEmpty {
            statusParts.append("\(result.inserted.count) item(ns) adicionado(s) à bandeja.")
        } else if !result.duplicates.isEmpty {
            statusParts.append("\(result.duplicates.count) item(ns) já estavam na bandeja.")
        }

        if fallbackMoveCount > 0 {
            statusParts.append("\(fallbackMoveCount) item(ns) movido(s) por cópia + remoção.")
        }

        if failedCount > 0 {
            statusParts.append("\(failedCount) item(ns) não puderam ser adicionados à bandeja.")
        }

        if !result.skippedForLimit.isEmpty {
            statusParts.append("Limite da bandeja atingido (\(collection.limit) itens).")
        }

        statusMessage = statusParts.last

        savePendingItems()
    }

    func removeItem(_ item: Item) {
        // "Remover" da bandeja passa a significar devolver para a origem quando existir.
        let removedFromTray: Bool
        if let original = item.originalURL,
           moveItemBackToOrigin(stagedURL: item.url, originalURL: original) {
            removedFromTray = true
            statusMessage = "Item devolvido para a origem."
        } else if item.originalURL == nil, deleteStagedItem(at: item.url) {
            removedFromTray = true
            statusMessage = "Item removido da bandeja."
        } else {
            removedFromTray = false
            statusMessage = "Não foi possível retirar este item da bandeja."
        }

        guard removedFromTray else {
            return
        }

        collection.remove(item.url)
        items.removeAll { $0.id == item.id }
        thumbnailCache.removeValue(forKey: item.url)
        thumbnailLoadingInProgress.remove(item.url)
        savePendingItems()
    }

    func consumeItemAfterExternalDrop(sourceURL: URL, destinationURL: URL? = nil) {
        let itemID = TransferItemCollection.canonicalPath(for: sourceURL)
        guard let index = items.firstIndex(where: { $0.id == itemID }) else {
            return
        }

        let item = items[index]
        collection.remove(item.url)
        items.remove(at: index)
        thumbnailCache.removeValue(forKey: item.url)
        thumbnailLoadingInProgress.remove(item.url)
        savePendingItems()
    }

    func clearItems() {
        restorePendingItemsToOriginBeforeClosingTray()
    }

    func restorePendingItemsToOriginBeforeClosingTray() {
        guard !items.isEmpty else {
            return
        }

        var restored = 0
        var discarded = 0
        var remainingItems: [Item] = []

        for item in items {
            guard let original = item.originalURL else {
                if item.shouldDeleteOnClose {
                    if deleteStagedItem(at: item.url) {
                        discarded += 1
                        collection.remove(item.url)
                        thumbnailCache.removeValue(forKey: item.url)
                        thumbnailLoadingInProgress.remove(item.url)
                    } else {
                        remainingItems.append(item)
                    }
                } else {
                    remainingItems.append(item)
                }
                continue
            }

            if moveItemBackToOrigin(stagedURL: item.url, originalURL: original) {
                restored += 1
                collection.remove(item.url)
                thumbnailCache.removeValue(forKey: item.url)
                thumbnailLoadingInProgress.remove(item.url)
            } else {
                remainingItems.append(item)
            }
        }

        items = remainingItems
        lastMoveMap = []
        savePendingItems()

        let totalHandled = restored + discarded
        if totalHandled > 0 && remainingItems.isEmpty {
            if discarded > 0 {
                statusMessage = "Bandeja fechada: \(restored) restaurado(s), \(discarded) removido(s)."
            } else {
                statusMessage = "Bandeja fechada: \(restored) item(ns) voltaram para a origem."
            }
        } else if totalHandled > 0 && !remainingItems.isEmpty {
            if discarded > 0 {
                statusMessage = "Bandeja fechada: \(restored) restaurado(s), \(discarded) removido(s), \(remainingItems.count) pendente(s)."
            } else {
                statusMessage = "Bandeja fechada: \(restored) item(ns) restaurado(s), \(remainingItems.count) pendente(s)."
            }
        } else if restored > 0 && remainingItems.isEmpty {
            statusMessage = "Bandeja fechada: \(restored) item(ns) voltaram para a origem."
        }
    }

    func openInFinder(_ item: Item) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    func revealTrayFolderInFinder() {
        guard let trayDirectoryURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([trayDirectoryURL])
    }

    func chooseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Escolher"
        panel.message = "Selecione a pasta de destino para copiar/mover os arquivos da bandeja."

        guard panel.runModal() == .OK, let selectedURL = panel.url else {
            return
        }

        destinationURL = selectedURL
        saveDestinationBookmark(for: selectedURL)
        statusMessage = "Destino: \(selectedURL.lastPathComponent)"
    }

    func requestExecuteTransfer() {
        guard !items.isEmpty else {
            statusMessage = "Adicione arquivos na bandeja antes de executar."
            return
        }

        do {
            _ = try coordinator.validateDestination(destinationURL)
        } catch {
            statusMessage = "Selecione uma pasta de destino válida."
            return
        }

        if operation == .move {
            showMoveConfirmation = true
            return
        }

        executeTransfer()
    }

    func confirmMoveTransfer() {
        showMoveConfirmation = false
        executeTransfer()
    }

    func cancelMoveTransfer() {
        showMoveConfirmation = false
    }

    func undoLastMove() {
        guard !lastMoveMap.isEmpty else {
            statusMessage = "Nenhuma operação de move para desfazer."
            return
        }

        let moveMap = lastMoveMap
        lastMoveMap = []
        isProcessing = true
        statusMessage = "Desfazendo operação…"

        Task.detached(priority: .userInitiated) {
            var restored = 0
            var failed = 0

            for (source, destination) in moveMap {
                do {
                    if FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) {
                        try FileManager.default.moveItem(at: destination, to: source)
                        restored += 1
                    } else {
                        failed += 1
                    }
                } catch {
                    failed += 1
                }
            }

            await MainActor.run {
                self.isProcessing = false
                if failed > 0 {
                    self.statusMessage = "Desfeito: \(restored) restaurado(s), \(failed) não encontrado(s)."
                } else {
                    self.statusMessage = "Operação desfeita: \(restored) arquivo(s) restaurado(s)."
                }
            }
        }
    }

    // MARK: - Transfer Execution

    private func executeTransfer() {
        guard let destinationURL else {
            statusMessage = "Selecione uma pasta de destino válida."
            return
        }

        let itemURLs = items.map(\.url)
        let selectedOperation = operation
        let total = itemURLs.count
        isProcessing = true
        transferProgress = 0
        currentTransferName = ""
        statusMessage = "Iniciando transferência…"
        lastMoveMap = []

        Task.detached(priority: .userInitiated) {
            var allResults: [TransferExecutionResult] = []
            var moveMap: [(source: URL, destination: URL)] = []
            let coord = FileTransferCoordinator()

            let destinationAccess = destinationURL.startAccessingSecurityScopedResource()

            for (index, sourceURL) in itemURLs.enumerated() {
                await MainActor.run {
                    self.currentTransferName = sourceURL.lastPathComponent
                    self.transferProgress = Double(index) / Double(total)
                }

                let results: [TransferExecutionResult] = {
                    let access = sourceURL.startAccessingSecurityScopedResource()
                    defer { if access { sourceURL.stopAccessingSecurityScopedResource() } }
                    return coord.execute(items: [sourceURL], to: destinationURL, operation: selectedOperation)
                }()

                if selectedOperation == .move,
                   let result = results.first,
                   case .success = result.status,
                   let dest = result.destinationURL {
                    moveMap.append((source: sourceURL, destination: dest))
                }

                allResults.append(contentsOf: results)
            }

            if destinationAccess { destinationURL.stopAccessingSecurityScopedResource() }

            await MainActor.run {
                self.transferProgress = 1.0
                self.lastMoveMap = moveMap
                self.applyTransferResults(allResults, operation: selectedOperation, destinationURL: destinationURL)
            }
        }
    }

    private func applyTransferResults(
        _ results: [TransferExecutionResult],
        operation: TransferOperation,
        destinationURL: URL
    ) {
        var succeeded = 0
        var failed = 0
        var failedIDs: Set<String> = []

        for result in results {
            let itemID = TransferItemCollection.canonicalPath(for: result.sourceURL)

            switch result.status {
            case .success:
                succeeded += 1
                if let index = items.firstIndex(where: { $0.id == itemID }) {
                    items[index].status = .success
                }
            case .failure(let message):
                failed += 1
                failedIDs.insert(itemID)
                if let index = items.firstIndex(where: { $0.id == itemID }) {
                    items[index].status = .failure(message)
                }
            }
        }

        if operation == .move {
            let movedItems = items.filter { !failedIDs.contains($0.id) }
            for moved in movedItems {
                collection.remove(moved.url)
                thumbnailCache.removeValue(forKey: moved.url)
            }
            items.removeAll { !failedIDs.contains($0.id) }
        }

        isProcessing = false
        currentTransferName = ""

        if failed > 0 {
            statusMessage = "Concluído: \(succeeded) sucesso(s), \(failed) falha(s)."
        } else {
            statusMessage = "Concluído: \(succeeded) item(ns) processado(s)."
        }

        savePendingItems()
        sendCompletionNotification(succeeded: succeeded, failed: failed, destinationURL: destinationURL)
    }

    // MARK: - Thumbnails

    private nonisolated static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "gif", "tiff", "tif", "bmp", "webp"
    ]

    private func loadThumbnailIfNeeded(for url: URL) {
        guard thumbnailCache[url] == nil, !thumbnailLoadingInProgress.contains(url) else {
            return
        }
        thumbnailLoadingInProgress.insert(url)

        Task.detached(priority: .utility) { [weak self] in
            // NSImage(contentsOf:) is thread-safe; scaledToFit uses lockFocus (AppKit drawing)
            // and must run on main thread — do it in MainActor.run below.
            let raw = Self.loadRawImage(for: url)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.thumbnailLoadingInProgress.remove(url)
                self.thumbnailCache[url] = raw.map { $0.scaledToFit(CGSize(width: 120, height: 120)) }
                    ?? NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false))
                self.objectWillChange.send()
            }
        }
    }

    private nonisolated static func loadRawImage(for url: URL) -> NSImage? {
        let ext = url.pathExtension.lowercased()
        guard imageExtensions.contains(ext) else { return nil }
        let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? Int.max
        guard fileSize < 30_000_000 else { return nil }
        return NSImage(contentsOf: url)
    }

    // MARK: - Persistence

    func savePendingItems() {
        // Legacy key was URL-only and does not represent origin mapping anymore.
        UserDefaults.standard.removeObject(forKey: legacyPendingItemsKey)
    }

    private func loadPendingItems() {
        UserDefaults.standard.removeObject(forKey: legacyPendingItemsKey)

        guard let trayDirectoryURL,
              let urls = try? FileManager.default.contentsOfDirectory(
                  at: trayDirectoryURL,
                  includingPropertiesForKeys: nil,
                  options: [.skipsHiddenFiles]
              ),
              !urls.isEmpty else {
            return
        }

        let result = collection.add(urls)
        for url in result.inserted {
            let canonical = TransferItemCollection.canonicalPath(for: url)
            items.append(
                Item(
                    id: canonical,
                    url: url,
                    name: url.lastPathComponent,
                    byteSize: fileSize(for: url),
                    originalURL: nil,
                    shouldDeleteOnClose: false,
                    status: .ready
                )
            )
            loadThumbnailIfNeeded(for: url)
        }

        if !result.inserted.isEmpty {
            statusMessage = "\(result.inserted.count) item(ns) recuperado(s) da pasta Bandeja."
        }
    }

    private var trayDirectoryURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("FolderPeek", isDirectory: true)
            .appendingPathComponent("Bandeja", isDirectory: true)
    }

    @discardableResult
    private func ensureTrayDirectoryExists() -> URL? {
        guard let trayDirectoryURL else { return nil }
        do {
            try FileManager.default.createDirectory(at: trayDirectoryURL, withIntermediateDirectories: true)
            return trayDirectoryURL
        } catch {
            return nil
        }
    }

    private func stageFileIfNeeded(_ sourceURL: URL, trayDirectoryURL: URL) throws -> StagedFileResult {
        let sourceCanonical = TransferItemCollection.canonicalPath(for: sourceURL)
        let trayCanonical = TransferItemCollection.canonicalPath(for: trayDirectoryURL)

        if sourceCanonical.hasPrefix(trayCanonical + "/") || sourceCanonical == trayCanonical {
            return StagedFileResult(
                stagedURL: sourceURL,
                originalURL: nil,
                shouldDeleteOnClose: false,
                usedCopyThenDeleteFallback: false
            )
        }

        let targetURL = try availableDestinationURL(for: sourceURL, in: trayDirectoryURL)
        let access = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if access {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        do {
            try FileManager.default.moveItem(at: sourceURL, to: targetURL)
            return StagedFileResult(
                stagedURL: targetURL,
                originalURL: sourceURL,
                shouldDeleteOnClose: false,
                usedCopyThenDeleteFallback: false
            )
        } catch {
            try FileManager.default.copyItem(at: sourceURL, to: targetURL)
            do {
                if FileManager.default.fileExists(atPath: sourceURL.path(percentEncoded: false)) {
                    try FileManager.default.removeItem(at: sourceURL)
                }
            } catch {
                try? FileManager.default.removeItem(at: targetURL)
                throw error
            }

            return StagedFileResult(
                stagedURL: targetURL,
                originalURL: sourceURL,
                shouldDeleteOnClose: false,
                usedCopyThenDeleteFallback: true
            )
        }
    }

    private func moveItemBackToOrigin(stagedURL: URL, originalURL: URL) -> Bool {
        do {
            let hasAccess = originalURL.startAccessingSecurityScopedResource()
            defer {
                if hasAccess {
                    originalURL.stopAccessingSecurityScopedResource()
                }
            }

            let originalParent = originalURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: originalParent, withIntermediateDirectories: true)

            let targetURL = FileManager.default.fileExists(atPath: originalURL.path(percentEncoded: false))
                ? try availableDestinationURL(for: stagedURL, in: originalParent)
                : originalURL

            try FileManager.default.moveItem(at: stagedURL, to: targetURL)
            return true
        } catch {
            return false
        }
    }

    private func deleteStagedItem(at url: URL) -> Bool {
        do {
            let hasAccess = url.startAccessingSecurityScopedResource()
            defer {
                if hasAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
                try FileManager.default.removeItem(at: url)
            }
            return true
        } catch {
            return false
        }
    }

    private func normalizedFilePathURL(from url: URL) -> URL {
        guard url.isFileURL else { return url }
        if let filePathURL = (url as NSURL).filePathURL {
            return filePathURL.standardizedFileURL
        }
        return url.standardizedFileURL
    }

    private func availableDestinationURL(for sourceURL: URL, in destinationDirectory: URL) throws -> URL {
        let manager = FileManager.default
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let extensionPart = sourceURL.pathExtension

        var candidate = destinationDirectory.appendingPathComponent(sourceURL.lastPathComponent)
        if !manager.fileExists(atPath: candidate.path(percentEncoded: false)) {
            return candidate
        }

        var suffix = 2
        while true {
            let renamed = extensionPart.isEmpty
                ? "\(baseName) (\(suffix))"
                : "\(baseName) (\(suffix)).\(extensionPart)"
            candidate = destinationDirectory.appendingPathComponent(renamed)
            if !manager.fileExists(atPath: candidate.path(percentEncoded: false)) {
                return candidate
            }
            suffix += 1
        }
    }

    // MARK: - Notifications

    private func sendCompletionNotification(succeeded: Int, failed: Int, destinationURL: URL) {
        guard succeeded > 0 else { return }
        let opName = operation == .copy ? "copiado(s)" : "movido(s)"
        let destName = destinationURL.lastPathComponent

        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else { return }

            let content = UNMutableNotificationContent()
            content.title = "Transferência concluída"
            content.body = failed > 0
                ? "\(succeeded) arquivo(s) \(opName) para \(destName). \(failed) com falha."
                : "\(succeeded) arquivo(s) \(opName) para \(destName)."
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: "transfer-\(UUID().uuidString)",
                content: content,
                trigger: nil
            )
            UNUserNotificationCenter.current().add(request)
        }
    }

    // MARK: - Helpers

    private func fileSize(for url: URL) -> Int64? {
        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .totalFileAllocatedSizeKey])
            if let totalSize = values.totalFileAllocatedSize { return Int64(totalSize) }
            if let fileSize = values.fileSize { return Int64(fileSize) }
        } catch {}
        return nil
    }

    private func saveDestinationBookmark(for url: URL) {
        do {
            let bookmark = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(bookmark, forKey: destinationBookmarkKey)
        } catch {
            statusMessage = "Não foi possível salvar o destino selecionado."
        }
    }

    private func loadDestinationBookmark() {
        guard let data = UserDefaults.standard.data(forKey: destinationBookmarkKey) else {
            return
        }

        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope, .withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            destinationURL = url

            if isStale {
                saveDestinationBookmark(for: url)
            }
        } catch {
            destinationURL = nil
        }
    }
}

// MARK: - NSImage Thumbnail Helper

private extension NSImage {
    func scaledToFit(_ targetSize: CGSize) -> NSImage {
        let aspectRatio = size.width / max(size.height, 1)
        let targetAspect = targetSize.width / max(targetSize.height, 1)
        let scaledSize: CGSize
        if aspectRatio > targetAspect {
            scaledSize = CGSize(width: targetSize.width, height: targetSize.width / max(aspectRatio, 1))
        } else {
            scaledSize = CGSize(width: targetSize.height * aspectRatio, height: targetSize.height)
        }
        let result = NSImage(size: scaledSize)
        result.lockFocus()
        draw(in: NSRect(origin: .zero, size: scaledSize),
             from: NSRect(origin: .zero, size: size),
             operation: .copy,
             fraction: 1.0)
        result.unlockFocus()
        return result
    }
}
