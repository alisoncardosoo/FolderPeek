import XCTest
@testable import FolderPeekCore

final class FileTransferCoordinatorTests: XCTestCase {
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

    func testValidateDestinationRejectsMissingPath() {
        let coordinator = FileTransferCoordinator()

        XCTAssertThrowsError(try coordinator.validateDestination(nil)) { error in
            XCTAssertEqual(error as? FileTransferCoordinatorError, .destinationMissing)
        }
    }

    func testValidateDestinationRejectsFiles() throws {
        let coordinator = FileTransferCoordinator()
        let fileURL = tempURL.appendingPathComponent("arquivo.txt")
        try "conteudo".write(to: fileURL, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try coordinator.validateDestination(fileURL)) { error in
            XCTAssertEqual(error as? FileTransferCoordinatorError, .destinationNotDirectory)
        }
    }

    func testCopyKeepsSourceAndGeneratesConflictSafeName() throws {
        let coordinator = FileTransferCoordinator()
        let source = tempURL.appendingPathComponent("origem.txt")
        let destination = tempURL.appendingPathComponent("destino", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try "fonte".write(to: source, atomically: true, encoding: .utf8)
        try "existente".write(to: destination.appendingPathComponent("origem.txt"), atomically: true, encoding: .utf8)

        let result = coordinator.execute(items: [source], to: destination, operation: .copy)

        XCTAssertEqual(result.count, 1)
        guard case .success = result[0].status else {
            return XCTFail("Esperava sucesso na cópia")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertEqual(result[0].destinationURL?.lastPathComponent, "origem (2).txt")
    }

    func testMoveRemovesSourceOnSuccess() throws {
        let coordinator = FileTransferCoordinator()
        let source = tempURL.appendingPathComponent("mover.txt")
        let destination = tempURL.appendingPathComponent("destino", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try "move".write(to: source, atomically: true, encoding: .utf8)

        let result = coordinator.execute(items: [source], to: destination, operation: .move)

        guard case .success = result[0].status else {
            return XCTFail("Esperava sucesso na movimentação")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.appendingPathComponent("mover.txt").path))
    }

    func testExecuteReturnsFailureWhenSourceIsMissing() throws {
        let coordinator = FileTransferCoordinator()
        let destination = tempURL.appendingPathComponent("destino", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let missing = tempURL.appendingPathComponent("nao-existe.txt")

        let result = coordinator.execute(items: [missing], to: destination, operation: .copy)

        guard case .failure(let message) = result[0].status else {
            return XCTFail("Esperava falha para arquivo inexistente")
        }
        XCTAssertFalse(message.isEmpty)
    }
}
