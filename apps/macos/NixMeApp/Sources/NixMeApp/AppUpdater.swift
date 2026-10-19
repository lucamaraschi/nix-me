import SwiftUI

#if canImport(Sparkle)
import Sparkle
#endif

@MainActor
final class AppUpdater: ObservableObject {
#if canImport(Sparkle)
    static let canCheckForUpdates = true

    private let controller: SPUStandardUpdaterController

    init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
#else
    static let canCheckForUpdates = false

    func checkForUpdates() {}
#endif
}
