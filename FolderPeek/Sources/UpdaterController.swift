import Foundation
import Sparkle

@MainActor
final class UpdaterController: ObservableObject {
    private let standardUpdaterController: SPUStandardUpdaterController

    init() {
        standardUpdaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    func checkForUpdates() {
        standardUpdaterController.checkForUpdates(nil)
    }
}
