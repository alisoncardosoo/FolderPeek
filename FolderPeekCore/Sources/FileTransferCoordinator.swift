import Foundation

public enum FileTransferCoordinatorError: Error, Equatable {
    case destinationMissing
    case destinationNotDirectory
}

public struct FileTransferCoordinator {
    public init() {}

    public func validateDestination(_ destination: URL?) throws -> URL {
        guard let destination else {
            throw FileTransferCoordinatorError.destinationMissing
        }

        var isDirectory = ObjCBool(false)
        let exists = FileManager.default.fileExists(atPath: destination.path, isDirectory: &isDirectory)

        guard exists, isDirectory.boolValue else {
            throw FileTransferCoordinatorError.destinationNotDirectory
        }

        return destination
    }

    public func execute(items: [URL], to destination: URL, operation: TransferOperation) -> [TransferExecutionResult] {
        items.map { sourceURL in
            transferItem(sourceURL, to: destination, operation: operation)
        }
    }

    private func transferItem(_ sourceURL: URL, to destinationDirectory: URL, operation: TransferOperation) -> TransferExecutionResult {
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: sourceURL.path) else {
            return TransferExecutionResult(
                sourceURL: sourceURL,
                destinationURL: nil,
                status: .failure("Arquivo de origem não encontrado.")
            )
        }

        do {
            let targetURL = try availableDestinationURL(for: sourceURL, destinationDirectory: destinationDirectory)
            switch operation {
            case .copy:
                try fileManager.copyItem(at: sourceURL, to: targetURL)
            case .move:
                try fileManager.moveItem(at: sourceURL, to: targetURL)
            }

            return TransferExecutionResult(sourceURL: sourceURL, destinationURL: targetURL, status: .success)
        } catch {
            return TransferExecutionResult(
                sourceURL: sourceURL,
                destinationURL: nil,
                status: .failure(error.localizedDescription)
            )
        }
    }

    private func availableDestinationURL(for sourceURL: URL, destinationDirectory: URL) throws -> URL {
        let fileManager = FileManager.default
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let extensionPart = sourceURL.pathExtension

        var candidateURL = destinationDirectory.appendingPathComponent(sourceURL.lastPathComponent)
        if !fileManager.fileExists(atPath: candidateURL.path) {
            return candidateURL
        }

        var suffix = 2
        while true {
            let renamed = extensionPart.isEmpty
                ? "\(baseName) (\(suffix))"
                : "\(baseName) (\(suffix)).\(extensionPart)"
            candidateURL = destinationDirectory.appendingPathComponent(renamed)

            if !fileManager.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }

            suffix += 1
        }
    }
}
