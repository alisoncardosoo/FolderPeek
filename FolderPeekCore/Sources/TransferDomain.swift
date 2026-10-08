import Foundation
import CoreGraphics

public enum TransferOperation: String, CaseIterable, Codable, Sendable {
    case copy
    case move
}

public enum TransferExecutionStatus: Equatable, Sendable {
    case success
    case failure(String)
}

public struct TransferExecutionResult: Equatable, Sendable {
    public let sourceURL: URL
    public let destinationURL: URL?
    public let status: TransferExecutionStatus

    public init(sourceURL: URL, destinationURL: URL?, status: TransferExecutionStatus) {
        self.sourceURL = sourceURL
        self.destinationURL = destinationURL
        self.status = status
    }
}

public struct TransferItemCollection: Sendable {
    public struct InsertResult: Equatable, Sendable {
        public let inserted: [URL]
        public let duplicates: [URL]
        public let skippedForLimit: [URL]

        public init(inserted: [URL], duplicates: [URL], skippedForLimit: [URL]) {
            self.inserted = inserted
            self.duplicates = duplicates
            self.skippedForLimit = skippedForLimit
        }
    }

    public let limit: Int
    public private(set) var items: [URL]
    private var canonicalPaths: Set<String>

    public init(limit: Int = 500, initialItems: [URL] = []) {
        self.limit = max(1, limit)
        self.items = []
        self.canonicalPaths = []
        _ = add(initialItems)
    }

    @discardableResult
    public mutating func add(_ urls: [URL]) -> InsertResult {
        var inserted: [URL] = []
        var duplicates: [URL] = []
        var skippedForLimit: [URL] = []

        for url in urls where url.isFileURL {
            guard items.count < limit else {
                skippedForLimit.append(url)
                continue
            }

            let canonicalPath = Self.canonicalPath(for: url)
            if canonicalPaths.contains(canonicalPath) {
                duplicates.append(url)
                continue
            }

            canonicalPaths.insert(canonicalPath)
            items.append(url)
            inserted.append(url)
        }

        return InsertResult(inserted: inserted, duplicates: duplicates, skippedForLimit: skippedForLimit)
    }

    public mutating func remove(_ url: URL) {
        let canonicalPath = Self.canonicalPath(for: url)
        items.removeAll { candidate in
            Self.canonicalPath(for: candidate) == canonicalPath
        }
        canonicalPaths.remove(canonicalPath)
    }

    public mutating func clear() {
        items.removeAll(keepingCapacity: true)
        canonicalPaths.removeAll(keepingCapacity: true)
    }

    public func contains(_ url: URL) -> Bool {
        canonicalPaths.contains(Self.canonicalPath(for: url))
    }

    public static func canonicalPath(for url: URL) -> String {
        let normalized = url.standardizedFileURL.resolvingSymlinksInPath()
        return normalized.path(percentEncoded: false)
    }
}

/// Detects intentional back-and-forth movement during a file drag, on either axis.
/// Coordinates are screen points; timestamps must use a monotonic clock.
public struct DragShakeDetector {
    private struct Sample {
        let point: CGPoint
        let time: TimeInterval
    }
    private var samples: [Sample] = []
    private let window: TimeInterval = 0.85
    private let minimumExcursion: CGFloat = 24

    public init() {}

    public mutating func reset() { samples.removeAll(keepingCapacity: true) }

    public mutating func record(_ point: CGPoint, at time: TimeInterval) -> Bool {
        samples.removeAll { time - $0.time > window || $0.time > time }
        samples.append(Sample(point: point, time: time))
        let horizontal: [CGFloat] = samples.map { sample in return CGFloat(sample.point.x) }
        let vertical: [CGFloat] = samples.map { sample in return CGFloat(sample.point.y) }
        if hasShake(horizontal) { return true }
        return hasShake(vertical)
    }

    private func hasShake(_ coordinates: [CGFloat]) -> Bool {
        guard var extreme = coordinates.first else { return false }
        var direction: CGFloat = 0
        var reversals = 0
        for coordinate in coordinates.dropFirst() {
            if direction == 0 {
                if abs(coordinate - extreme) >= minimumExcursion {
                    direction = coordinate > extreme ? 1 : -1
                    extreme = coordinate
                }
            } else if (coordinate - extreme) * direction >= 0 {
                extreme = coordinate
            } else if (extreme - coordinate) * direction >= minimumExcursion {
                direction = -direction
                extreme = coordinate
                reversals += 1
                if reversals >= 3 { return true }
            }
        }
        return false
    }
}

public enum TransferTrayActivationMode: String, CaseIterable, Sendable {
    case shake
    case finderExit
    case both

    public func shouldActivate(shakeDetected: Bool, exitedFinderWindow: Bool) -> Bool {
        switch self {
        case .shake: return shakeDetected
        case .finderExit: return exitedFinderWindow
        case .both: return shakeDetected || exitedFinderWindow
        }
    }
}

public struct FinderWindowExitDetector {
    private let windowFrame: CGRect?

    public init(windowFrame: CGRect?) { self.windowFrame = windowFrame }

    public func hasExited(at point: CGPoint) -> Bool {
        guard let windowFrame else { return false }
        // A small margin avoids opening on tiny movements along the window edge.
        return !windowFrame.insetBy(dx: -8, dy: -8).contains(point)
    }
}

/// Shared by the floating window and its grid, including two-line file labels.
public struct TransferTrayLayout {
    public let columns: Int
    public let rows: Int
    public let windowSize: CGSize

    public init(itemCount: Int) {
        let count = max(0, itemCount)
        columns = count > 4 ? 3 : 2
        // Count beyond nine is handled by scrolling, without enlarging the window.
        rows = max(1, min(3, (min(count, 9) + columns - 1) / columns))
        let width = 32 + columns * 100 + (columns - 1) * 10
        let height = max(220, 104 + rows * 102 + (rows - 1) * 12)
        windowSize = CGSize(width: Double(width), height: Double(height))
    }
}

/// Fixed tray anchors in AppKit's bottom-left screen coordinate system.
public enum TransferTrayPosition: String, CaseIterable, Identifiable, Sendable {
    case topRight
    case topLeft
    case bottomRight
    case bottomLeft
    case topCenter

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .topRight: "Canto superior direito"
        case .topLeft: "Canto superior esquerdo"
        case .bottomRight: "Canto inferior direito"
        case .bottomLeft: "Canto inferior esquerdo"
        case .topCenter: "Centro superior"
        }
    }

    public init(storedValue: String) {
        self = Self(rawValue: storedValue) ?? .topRight
    }

    public func frame(windowSize: CGSize, in visibleFrame: CGRect) -> CGRect {
        let margin: CGFloat = 8
        let available = visibleFrame.insetBy(
            dx: min(margin, visibleFrame.width / 2),
            dy: min(margin, visibleFrame.height / 2)
        )
        let size = CGSize(width: min(windowSize.width, available.width),
                          height: min(windowSize.height, available.height))
        let x: CGFloat
        switch self {
        case .topLeft, .bottomLeft: x = available.minX
        case .topRight, .bottomRight: x = available.maxX - size.width
        case .topCenter: x = available.midX - size.width / 2
        }
        let y: CGFloat
        switch self {
        case .bottomLeft, .bottomRight: y = available.minY
        case .topLeft, .topRight, .topCenter: y = available.maxY - size.height
        }
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }
}
