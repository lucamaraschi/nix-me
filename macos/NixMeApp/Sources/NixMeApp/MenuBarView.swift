import AppKit
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var store: DashboardStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if let snapshot = store.snapshot {
                status(snapshot)

                if !snapshot.updates.all.isEmpty {
                    Divider()
                    Text("Available updates")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    ForEach(Array(snapshot.updates.all.prefix(5))) { update in
                        HStack(spacing: 9) {
                            Image(systemName: updateSymbol(update))
                                .foregroundStyle(.orange)
                                .frame(width: 18)
                            Text(update.name)
                                .lineLimit(1)
                            Spacer()
                            Text(update.availableVersion ?? "Latest")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if snapshot.softwareUpdateCount > 5 {
                        Text("and \(snapshot.softwareUpdateCount - 5) more…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()
                Text("Checked \(relativeDate(snapshot.generatedAt))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let errorMessage = store.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Checking this Mac…")
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Button("Open Dashboard") {
                    openWindow(id: "dashboard")
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    Task { await store.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(store.isLoading)

                Spacer()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(width: 340)
        .task { store.startMonitoring() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "snowflake")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("Nix Me")
                    .font(.headline)
                Text(activityLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var activityLabel: String {
        if store.isUpdating {
            return "Updating \(store.updatingItemCount) item\(store.updatingItemCount == 1 ? "" : "s")…"
        }
        if store.isApplying {
            return "Applying configuration…"
        }
        return store.isLoading ? "Refreshing…" : "System manager"
    }

    private func status(_ snapshot: ManagementSnapshot) -> some View {
        VStack(spacing: 8) {
            MenuStatusRow(
                title: "Software updates",
                value: snapshot.softwareUpdateCount == 0 ? "Current" : "\(snapshot.softwareUpdateCount) available",
                color: snapshot.softwareUpdateCount == 0 ? .green : .orange
            )
            MenuStatusRow(
                title: "Configuration",
                value: configurationLabel(snapshot),
                color: snapshot.configuration.applyState == "current" ? .green : .orange
            )
            MenuStatusRow(
                title: "Projects",
                value: snapshot.projectAttentionCount == 0 ? "Current" : "\(snapshot.projectAttentionCount) need attention",
                color: snapshot.projectAttentionCount == 0 ? .green : .orange
            )
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
    }

    private func configurationLabel(_ snapshot: ManagementSnapshot) -> String {
        if snapshot.configuration.git?.dirty == true {
            return "Uncommitted changes"
        }
        if snapshot.configuration.git?.behind ?? 0 > 0 {
            return "Pull required"
        }
        if snapshot.configuration.git?.ahead ?? 0 > 0 {
            return "Push required"
        }
        switch snapshot.configuration.applyState {
        case "current": return "Applied"
        case "pending": return "Apply required"
        default: return "Unknown"
        }
    }

    private func updateSymbol(_ update: SoftwareUpdate) -> String {
        switch update.kind {
        case "cask": "macwindow"
        case "mas": "apple.logo"
        case "nixFlake": "snowflake"
        default: "terminal"
        }
    }

    private func relativeDate(_ value: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: value) else { return "recently" }
        return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
    }
}

private struct MenuStatusRow: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        HStack {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
        .font(.caption)
    }
}
