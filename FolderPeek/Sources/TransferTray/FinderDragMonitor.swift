import AppKit
import Foundation
import FolderPeekCore

final class FinderDragMonitor {
    private let pollInterval: TimeInterval
    private let onFilesDetected: ([URL]) -> Void

    private var timer: Timer?
    private var dragEventMonitor: Any?
    private var lastChangeCount = -1
    private var lastSeenCanonicalPaths: Set<String> = []

    init(pollInterval: TimeInterval = 0.10, onFilesDetected: @escaping ([URL]) -> Void) {
        self.pollInterval = pollInterval
        self.onFilesDetected = onFilesDetected
    }

    func start() {
        stop()

        // Captures drags from any app (Finder, VS Code, browser, etc.) via the global drag pasteboard.
        dragEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] _ in
            self?.pollDragPasteboard()
        }

        // Polling as complementary fallback for apps that don't trigger the global monitor reliably.
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.pollDragPasteboard()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil

        if let monitor = dragEventMonitor {
            NSEvent.removeMonitor(monitor)
            dragEventMonitor = nil
        }
    }

    deinit {
        stop()
    }

    private func pollDragPasteboard() {
        let pasteboard = NSPasteboard(name: .drag)
        let changeCount = pasteboard.changeCount
        guard changeCount != lastChangeCount else {
            return
        }

        lastChangeCount = changeCount

        let fileURLs = readFileURLs(from: pasteboard)
        guard !fileURLs.isEmpty else {
            lastSeenCanonicalPaths.removeAll(keepingCapacity: true)
            return
        }

        let canonicalPaths = Set(fileURLs.map { TransferItemCollection.canonicalPath(for: $0) })
        let freshURLs = fileURLs.filter {
            !lastSeenCanonicalPaths.contains(TransferItemCollection.canonicalPath(for: $0))
        }

        lastSeenCanonicalPaths = canonicalPaths

        guard !freshURLs.isEmpty else {
            return
        }

        onFilesDetected(freshURLs)
    }

    private func readFileURLs(from pasteboard: NSPasteboard) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]

        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL] else {
            return []
        }

        return urls.filter(\.isFileURL)
    }
}
