import XCTest
@testable import FolderPeekCore

final class FolderScannerTests: XCTestCase {
    private var tempURL: URL!

    override func setUpWithError() throws {
        tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempURL {
            try? FileManager.default.removeItem(at: tempURL)
        }
    }

    func testScansVisibleFolderItemsWithFoldersFirst() throws {
        let folder = tempURL.appendingPathComponent("Projetos", isDirectory: true)
        let file = tempURL.appendingPathComponent("anotacoes.txt")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try "ola".write(to: file, atomically: true, encoding: .utf8)

        let result = try FolderScanner().scan(url: tempURL)

        XCTAssertEqual(result.items.map(\.name), ["Projetos", "anotacoes.txt"])
        XCTAssertEqual(result.items.first?.kind, "Pasta")
        XCTAssertEqual(result.items.last?.byteSize, 3)
    }

    func testHidesDotFilesByDefault() throws {
        try "segredo".write(to: tempURL.appendingPathComponent(".env"), atomically: true, encoding: .utf8)
        try "publico".write(to: tempURL.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        let result = try FolderScanner().scan(url: tempURL)

        XCTAssertEqual(result.items.map(\.name), ["README.md"])
    }

    func testCanShowHiddenFiles() throws {
        try "segredo".write(to: tempURL.appendingPathComponent(".env"), atomically: true, encoding: .utf8)

        let result = try FolderScanner().scan(url: tempURL, preferences: PreviewPreferences(showHiddenFiles: true))

        XCTAssertEqual(result.items.map(\.name), [".env"])
    }

    func testRespectsItemLimit() throws {
        for index in 0..<40 {
            try "\(index)".write(to: tempURL.appendingPathComponent("file-\(index).txt"), atomically: true, encoding: .utf8)
        }

        let result = try FolderScanner().scan(url: tempURL, preferences: PreviewPreferences(itemLimit: 25))

        XCTAssertEqual(result.items.count, 25)
        XCTAssertTrue(result.reachedLimit)
        XCTAssertFalse(result.warnings.isEmpty)
    }
}
