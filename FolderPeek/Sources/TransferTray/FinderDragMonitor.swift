import AppKit
import Foundation
import FolderPeekCore

final class FinderDragMonitor {
    private let pollInterval: TimeInterval
    private let onFilesDetected: ([URL], NSPoint) -> Void
    private let onDragEnded: () -> Void
    private var timer: Timer?
    private var globalEventMonitor: Any?
    private var localEventMonitor: Any?
    private var lastChangeCount = NSPasteboard(name: .drag).changeCount
    private var isTrackingPress = false
    private var pressStartedInFinder = false
    private var pressOrigin = NSPoint.zero
    private var fileURLs: [URL] = []
    private var shakeDetector = DragShakeDetector()
    private var finderWindowExitDetector = FinderWindowExitDetector(windowFrame: nil)
    private var didShowTrayForCurrentDrag = false

    init(
        pollInterval: TimeInterval = 1.0 / 60.0,
        onFilesDetected: @escaping ([URL], NSPoint) -> Void,
        onDragEnded: @escaping () -> Void = {}
    ) {
        self.pollInterval = pollInterval
        self.onFilesDetected = onFilesDetected
        self.onDragEnded = onDragEnded
    }

    func start() {
        stop()
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handle(event)
        }
        // Global monitors exclude our own windows, including a release over the tray.
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handle(event)
            return event
        }
        let timer = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.pollDragPasteboard()
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let globalEventMonitor { NSEvent.removeMonitor(globalEventMonitor) }
        if let localEventMonitor { NSEvent.removeMonitor(localEventMonitor) }
        globalEventMonitor = nil
        localEventMonitor = nil
        resetPress()
    }

    deinit { stop() }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            resetPress()
            beginPressIfNeeded()
        case .leftMouseUp:
            endPress()
        default:
            pollDragPasteboard()
        }
    }

    private func beginPressIfNeeded() {
        guard !isTrackingPress else { return }
        isTrackingPress = true
        pressOrigin = NSEvent.mouseLocation
        pressStartedInFinder = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder"
        if pressStartedInFinder {
            finderWindowExitDetector = FinderWindowExitDetector(
                windowFrame: finderWindowFrame(at: pressOrigin)
            )
        }
    }

    private func pollDragPasteboard() {
        // A drag pasteboard retains its contents after release. Never interpret idle
        // movement, a click, or a window drag as a new file drag.
        guard NSEvent.pressedMouseButtons & 1 != 0 else {
            endPress()
            return
        }
        beginPressIfNeeded()
        let pasteboard = NSPasteboard(name: .drag)
        if pasteboard.changeCount != lastChangeCount {
            lastChangeCount = pasteboard.changeCount
            // Clicking an inactive Finder window can activate it after mouse-down.
            if !pressStartedInFinder,
               NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder" {
                pressStartedInFinder = true
                finderWindowExitDetector = FinderWindowExitDetector(windowFrame: finderWindowFrame(at: pressOrigin))
            }
            fileURLs = pressStartedInFinder ? readFileURLs(from: pasteboard) : []
        }
        guard pressStartedInFinder, !fileURLs.isEmpty, !didShowTrayForCurrentDrag else { return }
        guard UserDefaults.standard.object(forKey: "autoShowOnDrag") as? Bool ?? true else { return }
        let point = NSEvent.mouseLocation
        let mode = TransferTrayActivationMode(
            rawValue: UserDefaults.standard.string(forKey: "transferTrayActivationMode") ?? ""
        ) ?? .both
        let shakeDetected = shakeDetector.record(point, at: ProcessInfo.processInfo.systemUptime)
        guard mode.shouldActivate(
            shakeDetected: shakeDetected,
            exitedFinderWindow: finderWindowExitDetector.hasExited(at: point)
        ) else { return }
        didShowTrayForCurrentDrag = true
        onFilesDetected(fileURLs, point)
    }

    private func endPress() {
        let shouldNotify = didShowTrayForCurrentDrag
        resetPress()
        if shouldNotify { onDragEnded() }
    }

    private func resetPress() {
        lastChangeCount = NSPasteboard(name: .drag).changeCount
        isTrackingPress = false
        pressStartedInFinder = false
        fileURLs = []
        shakeDetector.reset()
        finderWindowExitDetector = FinderWindowExitDetector(windowFrame: nil)
        didShowTrayForCurrentDrag = false
    }

    private func readFileURLs(from pasteboard: NSPasteboard) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        return (pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL] ?? [])
            .filter(\.isFileURL)
    }

    private func finderWindowFrame(at point: NSPoint) -> CGRect? {
        guard let finderPID = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              let windows = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
              ) as? [[String: Any]],
              let screenTop = NSScreen.screens.first?.frame.maxY else { return nil }

        // WindowServer uses top-left coordinates; AppKit uses bottom-left coordinates.
        // Capture the source window, so entering another Finder window still counts as exit.
        for window in windows {
            guard (window[kCGWindowOwnerPID as String] as? Int) == Int(finderPID),
                  (window[kCGWindowLayer as String] as? Int) == 0,
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let cgFrame = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { continue }
            let frame = CGRect(x: cgFrame.minX, y: screenTop - cgFrame.maxY,
                               width: cgFrame.width, height: cgFrame.height)
            if frame.contains(point) { return frame }
        }
        return nil
    }
}
