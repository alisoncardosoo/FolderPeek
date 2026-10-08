import XCTest
@testable import FolderPeekCore

final class TransferDomainTests: XCTestCase {
    func testCollectionDeduplicatesCanonicalPaths() throws {
        var collection = TransferItemCollection(limit: 10)
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let file = tempDir.appendingPathComponent("arquivo.txt")
        try "teste".write(to: file, atomically: true, encoding: .utf8)

        let aliasPath = tempDir.appendingPathComponent("./arquivo.txt")
        let result = collection.add([file, aliasPath])

        XCTAssertEqual(result.inserted.count, 1)
        XCTAssertEqual(result.duplicates.count, 1)
        XCTAssertEqual(collection.items.count, 1)
    }

    func testCollectionRespectsLimit() {
        var collection = TransferItemCollection(limit: 2)
        let files = [
            URL(fileURLWithPath: "/tmp/a.txt"),
            URL(fileURLWithPath: "/tmp/b.txt"),
            URL(fileURLWithPath: "/tmp/c.txt")
        ]

        let result = collection.add(files)

        XCTAssertEqual(result.inserted.count, 2)
        XCTAssertEqual(result.skippedForLimit.count, 1)
        XCTAssertEqual(collection.items.count, 2)
    }

    func testCollectionClearRemovesAllItems() {
        var collection = TransferItemCollection(limit: 10)
        _ = collection.add([URL(fileURLWithPath: "/tmp/a.txt")])

        collection.clear()

        XCTAssertTrue(collection.items.isEmpty)
    }
}

final class DragShakeDetectorTests: XCTestCase {
    func testHorizontalAndVerticalShakes() {
        for vertical in [false, true] {
            var detector = DragShakeDetector()
            let positions: [CGFloat] = [0, 40, -40, 40, -40]
            for (index, value) in positions.enumerated() {
                let point = vertical ? CGPoint(x: 0, y: value) : CGPoint(x: value, y: 0)
                XCTAssertEqual(detector.record(point, at: Double(index) * 0.12), index == 4)
            }
        }
    }

    func testNormalDragAndSmallJitterDoNotOpenTray() {
        var detector = DragShakeDetector()
        for index in 0..<40 {
            XCTAssertFalse(detector.record(CGPoint(x: Double(index * 10), y: Double(index % 2 * 8)), at: Double(index) * 0.02))
        }
    }

    func testSlowChangesOfDirectionDoNotCountAsShake() {
        var detector = DragShakeDetector()
        for (index, x) in [0, 50, -50, 50, -50].enumerated() {
            XCTAssertFalse(detector.record(CGPoint(x: Double(x), y: 0), at: Double(index) * 0.5))
        }
    }

    func testResetDoesNotCarryGestureIntoNextDrag() {
        var detector = DragShakeDetector()
        for (index, x) in [0, 50, -50, 50].enumerated() {
            XCTAssertFalse(detector.record(CGPoint(x: Double(x), y: 0), at: Double(index) * 0.1))
        }
        detector.reset()
        XCTAssertFalse(detector.record(CGPoint(x: -50, y: 0), at: 0.4))
    }

    func testPauseExpiresPreviousGesture() {
        var detector = DragShakeDetector()
        for (index, x) in [0, 50, -50, 50].enumerated() {
            XCTAssertFalse(detector.record(CGPoint(x: Double(x), y: 0), at: Double(index) * 0.1))
        }
        XCTAssertFalse(detector.record(CGPoint(x: -50, y: 0), at: 2))
    }
}

final class TransferTrayActivationTests: XCTestCase {
    func testEachModeAcceptsOnlyItsConfiguredTrigger() {
        for mode in TransferTrayActivationMode.allCases {
            XCTAssertFalse(mode.shouldActivate(shakeDetected: false, exitedFinderWindow: false))
            XCTAssertTrue(mode.shouldActivate(shakeDetected: true, exitedFinderWindow: true))
            XCTAssertEqual(mode.shouldActivate(shakeDetected: true, exitedFinderWindow: false), mode != .finderExit)
            XCTAssertEqual(mode.shouldActivate(shakeDetected: false, exitedFinderWindow: true), mode != .shake)
        }
    }

    func testWindowExitRequiresLeavingSourceFrameAndMargin() {
        let detector = FinderWindowExitDetector(windowFrame: CGRect(x: 100, y: 200, width: 500, height: 400))
        XCTAssertFalse(detector.hasExited(at: CGPoint(x: 350, y: 400)))
        XCTAssertFalse(detector.hasExited(at: CGPoint(x: 605, y: 400)))
        XCTAssertTrue(detector.hasExited(at: CGPoint(x: 610, y: 400)))
        XCTAssertTrue(detector.hasExited(at: CGPoint(x: 90, y: 400)))
        XCTAssertTrue(detector.hasExited(at: CGPoint(x: 350, y: 190)))
        XCTAssertTrue(detector.hasExited(at: CGPoint(x: 350, y: 610)))
    }

    func testMissingSourceWindowDoesNotCauseImmediateOpening() {
        XCTAssertFalse(FinderWindowExitDetector(windowFrame: nil).hasExited(at: CGPoint(x: 999, y: 999)))
    }

    func testWindowExitOnScreenWithNegativeCoordinates() {
        let detector = FinderWindowExitDetector(windowFrame: CGRect(x: -1500, y: -900, width: 500, height: 400))
        XCTAssertFalse(detector.hasExited(at: CGPoint(x: -1300, y: -700)))
        XCTAssertTrue(detector.hasExited(at: CGPoint(x: -980, y: -700)))
    }

    func testModeRoundTripsStoredValue() {
        for mode in TransferTrayActivationMode.allCases {
            XCTAssertEqual(TransferTrayActivationMode(rawValue: mode.rawValue), mode)
        }
    }
}

final class TransferTrayLayoutTests: XCTestCase {
    func testLayoutGrowsWithItemCount() {
        let expected = [(0, 2, 1), (1, 2, 1), (2, 2, 1), (3, 2, 2), (4, 2, 2), (5, 3, 2), (6, 3, 2), (7, 3, 3), (8, 3, 3), (9, 3, 3)]
        var previousSize = CGSize.zero
        for (count, columns, rows) in expected {
            let layout = TransferTrayLayout(itemCount: count)
            XCTAssertEqual(layout.columns, columns)
            XCTAssertEqual(layout.rows, rows)
            XCTAssertTrue(layout.windowSize.width >= previousSize.width)
            XCTAssertTrue(layout.windowSize.height >= previousSize.height)
            previousSize = layout.windowSize
        }
    }

    func testOverflowKeepsThreeByThreeWindow() {
        let maximum = TransferTrayLayout(itemCount: 9)
        for count in [10, 20, 500, Int.max] {
            let layout = TransferTrayLayout(itemCount: count)
            XCTAssertEqual(layout.columns, 3)
            XCTAssertEqual(layout.rows, 3)
            XCTAssertEqual(layout.windowSize, maximum.windowSize)
        }
    }

    func testRemovalShrinksLayoutAndNegativeCountUsesEmptyLayout() {
        XCTAssertTrue(TransferTrayLayout(itemCount: 4).windowSize.width < TransferTrayLayout(itemCount: 5).windowSize.width)
        XCTAssertTrue(TransferTrayLayout(itemCount: 6).windowSize.height < TransferTrayLayout(itemCount: 7).windowSize.height)
        XCTAssertEqual(TransferTrayLayout(itemCount: -1).windowSize, TransferTrayLayout(itemCount: 0).windowSize)
    }
}

final class TransferTrayPositionTests: XCTestCase {
    func testDefaultAndUnknownValuesUseTopRight() {
        XCTAssertEqual(TransferTrayPosition(storedValue: ""), .topRight)
        XCTAssertEqual(TransferTrayPosition(storedValue: "obsolete"), .topRight)
        for position in TransferTrayPosition.allCases {
            XCTAssertEqual(TransferTrayPosition(storedValue: position.rawValue), position)
        }
    }

    func testFiveAnchorsOnOffsetDisplay() {
        let visible = CGRect(x: -1920, y: 40, width: 1920, height: 1040)
        let size = CGSize(width: 360, height: 240)
        let expected: [TransferTrayPosition: CGPoint] = [
            .topRight: CGPoint(x: -368, y: 832),
            .topLeft: CGPoint(x: -1912, y: 832),
            .bottomRight: CGPoint(x: -368, y: 48),
            .bottomLeft: CGPoint(x: -1912, y: 48),
            .topCenter: CGPoint(x: -1140, y: 832)
        ]
        for (position, origin) in expected {
            let frame = position.frame(windowSize: size, in: visible)
            XCTAssertEqual(frame.origin, origin)
            XCTAssertEqual(frame.size, size)
            XCTAssertTrue(visible.contains(frame))
        }
    }

    func testResizingKeepsSelectedAnchor() {
        let visible = CGRect(x: 100, y: 120, width: 1440, height: 800)
        for position in TransferTrayPosition.allCases {
            let small = position.frame(windowSize: CGSize(width: 300, height: 240), in: visible)
            let large = position.frame(windowSize: CGSize(width: 360, height: 374), in: visible)
            switch position {
            case .topLeft, .bottomLeft: XCTAssertEqual(small.minX, large.minX)
            case .topRight, .bottomRight: XCTAssertEqual(small.maxX, large.maxX)
            case .topCenter: XCTAssertEqual(small.midX, large.midX)
            }
            switch position {
            case .bottomLeft, .bottomRight: XCTAssertEqual(small.minY, large.minY)
            default: XCTAssertEqual(small.maxY, large.maxY)
            }
        }
    }

    func testOversizedTrayFitsSmallDisplay() {
        let visible = CGRect(x: 50, y: -400, width: 320, height: 200)
        for position in TransferTrayPosition.allCases {
            let frame = position.frame(windowSize: CGSize(width: 360, height: 374), in: visible)
            XCTAssertEqual(frame.size, CGSize(width: 304, height: 184))
            XCTAssertTrue(visible.contains(frame))
        }
    }
}
