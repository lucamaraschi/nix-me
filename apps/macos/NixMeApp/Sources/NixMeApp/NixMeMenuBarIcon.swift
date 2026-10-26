import SwiftUI

enum MenuBarIndicator: Equatable {
    case current
    case updates(Int)
    case attention
    case critical
    case working

    static func resolve(
        setupNeedsAttention: Bool,
        hasError: Bool,
        isWorking: Bool,
        hasCriticalFailure: Bool,
        needsAttention: Bool,
        softwareUpdateCount: Int
    ) -> Self {
        if setupNeedsAttention || hasError || hasCriticalFailure {
            return .critical
        }
        if isWorking {
            return .working
        }
        if needsAttention {
            return .attention
        }
        if softwareUpdateCount > 0 {
            return .updates(softwareUpdateCount)
        }
        return .current
    }

    var accessibilityLabel: String {
        switch self {
        case .current:
            "Nix Me: current"
        case let .updates(count):
            "Nix Me: \(count) software update\(count == 1 ? "" : "s") available"
        case .attention:
            "Nix Me: changes need attention"
        case .critical:
            "Nix Me: action required"
        case .working:
            "Nix Me: operation in progress"
        }
    }
}

struct NixMeMenuBarIcon: View {
    let indicator: MenuBarIndicator

    var body: some View {
        Image(systemName: "square.3.layers.3d.top.filled")
            .symbolRenderingMode(.palette)
            .foregroundStyle(indicatorColor)
            .accessibilityLabel(indicator.accessibilityLabel)
            .help(indicator.accessibilityLabel)
    }

    private var indicatorColor: Color {
        switch indicator {
        case .current:
            .primary
        case .updates:
            .blue
        case .attention:
            .orange
        case .critical:
            .red
        case .working:
            .cyan
        }
    }
}
