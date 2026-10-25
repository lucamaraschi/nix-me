import Foundation

@MainActor
final class InstallationPowerAssertion: ObservableObject {
    @Published private(set) var isActive = false

    private let processInfo: ProcessInfo
    private var activity: NSObjectProtocol?

    init(enabled: Bool, processInfo: ProcessInfo = .processInfo) {
        self.processInfo = processInfo
        guard enabled else { return }

        activity = processInfo.beginActivity(
            options: [
                .userInitiated,
                .idleSystemSleepDisabled,
                .idleDisplaySleepDisabled,
            ],
            reason: "Nix Me is installing and activating this Mac's configuration"
        )
        isActive = activity != nil
    }

    deinit {
        if let activity {
            processInfo.endActivity(activity)
        }
    }
}
