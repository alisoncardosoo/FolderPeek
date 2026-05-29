import AppKit
import Foundation
import FolderPeekCore

final class FinderDragMonitor {
    private let pollInterval: TimeInterval
    private let onFilesDetected: ([URL], NSPoint) -> Void

    private var timer: Timer?
    private var dragEventMonitor: Any?
    private var lastChangeCount = -1
    private var lastSeenCanonicalPaths: Set<String> = []
    private var finderDragPending = false
    private var cachedFinderFrames: [CGRect] = []

    init(pollInterval: TimeInterval = 0.10, onFilesDetected: @escaping ([URL], NSPoint) -> Void) {
        self.pollInterval = pollInterval
        self.onFilesDetected = onFilesDetected
    }

    func start() {
        stop()

        // Monitors the global drag pasteboard; only fires when drag originates from Finder.
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

        if changeCount != lastChangeCount {
            lastChangeCount = changeCount
            lastSeenCanonicalPaths.removeAll(keepingCapacity: true)
            finderDragPending = false
            cachedFinderFrames = []

            if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder" {
                finderDragPending = true
                // Capture window frames once at drag start — avoids calling CGWindowListCopyWindowInfo on every poll tick.
                cachedFinderFrames = finderWindowFrames()
            }
        }

        guard finderDragPending else { return }

        let mouseLocationCG = mousePositionInCGCoordinates()
        guard !cachedFinderFrames.contains(where: { $0.contains(mouseLocationCG) }) else { return }

        finderDragPending = false
        cachedFinderFrames = []

        let fileURLs = readFileURLs(from: pasteboard)
        guard !fileURLs.isEmpty else { return }

        let canonicalPaths = Set(fileURLs.map { TransferItemCollection.canonicalPath(for: $0) })
        let freshURLs = fileURLs.filter {
            !lastSeenCanonicalPaths.contains(TransferItemCollection.canonicalPath(for: $0))
        }

        lastSeenCanonicalPaths = canonicalPaths

        guard !freshURLs.isEmpty else { return }

        onFilesDetected(freshURLs, NSEvent.mouseLocation)
    }

    private func mousePositionInCGCoordinates() -> CGPoint {
        let p = NSEvent.mouseLocation
        let screenHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGPoint(x: p.x, y: screenHeight - p.y)
    }

    private func finderWindowFrames() -> [CGRect] {
        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return [] }

        return list.compactMap { info -> CGRect? in
            guard (info[kCGWindowOwnerName as String] as? String) == "Finder",
                  let b = info[kCGWindowBounds as String] as? [String: CGFloat]
            else { return nil }
            return CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0,
                          width: b["Width"] ?? 0, height: b["Height"] ?? 0)
        }
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
