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
