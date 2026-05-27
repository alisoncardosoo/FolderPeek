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
        var status: ItemStatus
    }

    struct TransferRecord: Codable, Identifiable, Sendable {
        let id: UUID
        let date: Date
        let operation: TransferOperation
        let fileNames: [String]
        let destinationName: String
        let succeededCount: Int
        let failedCount: Int
    }

    @Published private(set) var items: [Item] = []
    @Published var operation: TransferOperation = .copy
    @Published private(set) var destinationURL: URL?
    @Published var isProcessing = false
    @Published var statusMessage: String?
    @Published var showMoveConfirmation = false
    @Published var transferProgress: Double = 0
    @Published var currentTransferName: String = ""
    @Published private(set) var transferHistory: [TransferRecord] = []

    private var thumbnailCache: [URL: NSImage] = [:]
    private var thumbnailLoadingInProgress: Set<URL> = []
    private let destinationBookmarkKey = "transferTrayDestinationBookmark"
    private let pendingItemsKey = "transferTrayPendingBookmarks"
    private let coordinator = FileTransferCoordinator()
    private var collection = TransferItemCollection(limit: 500)
    private var lastMoveMap: [(source: URL, destination: URL)] = []

    init() {
        loadDestinationBookmark()
        loadPendingItems()
        loadHistory()
    }

    var destinationPathText: String {
        destinationURL?.path(percentEncoded: false) ?? "Nenhuma pasta selecionada"
    }

    var trayTitle: String {
        guard let firstParent = items.first?.url.deletingLastPathComponent().lastPathComponent,
              !firstParent.isEmpty else {
            return "Bandeja"
        }
        return firstParent
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
        let result = collection.add(urls)

        for url in result.inserted {
            items.append(
                Item(
                    id: TransferItemCollection.canonicalPath(for: url),
                    url: url,
                    name: url.lastPathComponent,
                    byteSize: fileSize(for: url),
                    status: .ready
                )
            )
            loadThumbnailIfNeeded(for: url)
        }

        if !result.inserted.isEmpty {
            statusMessage = "\(result.inserted.count) item(ns) adicionado(s) à bandeja."
        } else if !result.duplicates.isEmpty {
            statusMessage = "\(result.duplicates.count) item(ns) já na bandeja."
        }

        if !result.skippedForLimit.isEmpty {
            statusMessage = "Limite da bandeja atingido (\(collection.limit) itens)."
        }
    }

    func removeItem(_ item: Item) {
        collection.remove(item.url)
        items.removeAll { $0.id == item.id }
        thumbnailCache.removeValue(forKey: item.url)
        thumbnailLoadingInProgress.remove(item.url)
        savePendingItems()
    }

    func clearItems() {
        collection.clear()
        items.removeAll(keepingCapacity: true)
        thumbnailCache.removeAll(keepingCapacity: true)
        thumbnailLoadingInProgress.removeAll(keepingCapacity: true)
        statusMessage = nil
        lastMoveMap = []
        savePendingItems()
    }

    func openInFinder(_ item: Item) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
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

        let record = TransferRecord(
            id: UUID(),
            date: Date(),
            operation: operation,
            fileNames: results.map { $0.sourceURL.lastPathComponent },
            destinationName: destinationURL.lastPathComponent,
            succeededCount: succeeded,
            failedCount: failed
        )
        saveHistoryRecord(record)
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
        var bookmarks: [Data] = []
        for item in items where item.status == .ready {
            if let data = try? item.url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            ) {
                bookmarks.append(data)
            }
        }
        UserDefaults.standard.set(bookmarks, forKey: pendingItemsKey)
    }

    private func loadPendingItems() {
        guard let bookmarkArray = UserDefaults.standard.array(forKey: pendingItemsKey) as? [Data],
              !bookmarkArray.isEmpty else {
            return
        }

        var restoredURLs: [URL] = []
        for data in bookmarkArray {
            var isStale = false
            guard let url = try? URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope, .withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) else { continue }

            if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
                restoredURLs.append(url)
            }
        }

        if !restoredURLs.isEmpty {
            addFiles(restoredURLs)
            statusMessage = "\(restoredURLs.count) item(ns) restaurado(s) da sessão anterior."
        }
    }

    // MARK: - History

    private var historyFileURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("FolderPeek", isDirectory: true)
            .appendingPathComponent("transfer-history.json")
    }

    private func loadHistory() {
        guard let url = historyFileURL,
              let data = try? Data(contentsOf: url),
              let records = try? JSONDecoder().decode([TransferRecord].self, from: data) else {
            return
        }
        transferHistory = records
    }

    private func saveHistoryRecord(_ record: TransferRecord) {
        transferHistory.insert(record, at: 0)
        if transferHistory.count > 100 {
            transferHistory = Array(transferHistory.prefix(100))
        }
        guard let url = historyFileURL else { return }
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(transferHistory) {
            try? data.write(to: url, options: .atomic)
        }
    }

    func clearHistory() {
        transferHistory.removeAll()
        if let url = historyFileURL {
            try? FileManager.default.removeItem(at: url)
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
