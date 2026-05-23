import XCTest
@testable import FolderPeekCore

final class ArchiveScannerTests: XCTestCase {
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

    func testReadsZipCentralDirectory() throws {
        let source = tempURL.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: source.appendingPathComponent("Imagens", isDirectory: true), withIntermediateDirectories: true)
        try "alpha".write(to: source.appendingPathComponent("Imagens/foto.txt"), atomically: true, encoding: .utf8)
        try "beta".write(to: source.appendingPathComponent("resumo.md"), atomically: true, encoding: .utf8)
        let zipURL = tempURL.appendingPathComponent("fixture.zip")

        try runZip(workingDirectory: source, destination: zipURL)

        let result = try ArchiveScanner().scan(url: zipURL)

        XCTAssertEqual(result.title, "fixture.zip")
        XCTAssertTrue(result.subtitle.contains("ZIP"))
        XCTAssertTrue(result.items.contains { $0.relativePath == "Imagens/foto.txt" })
        XCTAssertTrue(result.items.contains { $0.relativePath == "resumo.md" })
    }

    func testUnsupportedArchivesReturnFriendlyError() {
        let rarURL = tempURL.appendingPathComponent("demo.rar")

        XCTAssertThrowsError(try ArchiveScanner().scan(url: rarURL)) { error in
            XCTAssertEqual(error as? PreviewScanError, .unsupportedArchive("rar"))
        }
    }

    private func runZip(workingDirectory: URL, destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = workingDirectory
        process.arguments = ["-qr", destination.path, "."]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }
}
