import AppKit
import SwiftUI

struct SettingsAccessView: View {
    let application: AppStateSettingsApplication
    let failure: AppSettingsReadFailure
    let review: AppSettingsReview?
    let isChecking: Bool
    let canVerify: Bool
    let verify: () -> Void
    let finish: () -> Void

    @State private var identity = RunningAppIdentity.current()
    @State private var requestedAt: Date?
    @State private var recheckOnReturn = false
    @State private var settingsError: String?

    private var verification: SettingsAccessVerification.State {
        SettingsAccessVerification.state(requestedAt: requestedAt, review: review, busy: isChecking)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text(verification == .readable ? "Access restored" : "Read \(application.name)'s preferences")
                .font(.title2.weight(.semibold))
            Text("This check won't save or change your settings.")
                .foregroundStyle(.secondary)
            if verification != .readable {
                if failure.kind == .privacy {
                    section("1. Allow access in macOS") {
                        Text("Add this copy of Nix Me to Full Disk Access and turn it on. Restart Nix Me if macOS asks.")
                        HStack {
                            Button("Open Full Disk Access", systemImage: "gearshape") { openPrivacy() }
                                .buttonStyle(OxideButtonStyle(variant: .primary))
                            Button("Show Nix Me in Finder", systemImage: "folder") {
                                NSWorkspace.shared.activateFileViewerSelecting([identity.bundleURL])
                            }
                            .buttonStyle(OxideButtonStyle(variant: .secondary))
                        }
                        Text("Optional: this allows access to sensitive data beyond settings. You can skip this app instead.")
                            .font(.callout).foregroundStyle(.secondary)
                        if let settingsError { Text(settingsError).foregroundStyle(OxidePalette.amber) }
                    }
                } else {
                    section("1. Check file permissions") {
                        Text("In Finder, open Get Info > Sharing & Permissions. Ask the owner or an administrator for read access.")
                        sourceFiles
                        Text("Full Disk Access won't fix file ownership. Nix Me won't change these permissions.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
            }
            section(verification == .readable ? "Ready to review" : "2. Check access") {
                verificationStatus
                HStack {
                    if verification == .readable {
                        Button("Review Preferences", action: finish)
                            .buttonStyle(OxideButtonStyle(variant: .primary))
                    } else {
                        Button(isChecking ? "Checking…" : "Check Access", systemImage: "arrow.clockwise") { checkAccess() }
                            .buttonStyle(OxideButtonStyle(variant: .primary))
                            .disabled(isChecking || !canVerify)
                        Button("Not Now", action: finish)
                            .buttonStyle(OxideButtonStyle(variant: .secondary))
                    }
                }
                if !canVerify {
                    Text("Go back and allow the file preview first.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            DisclosureGroup("Details") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Original error").font(.headline)
                    Text(failure.message).font(.callout).textSelection(.enabled)
                    if verification == .otherFailure, let error = review?.error {
                        Text("Latest error").font(.headline)
                        Text(error).font(.callout).textSelection(.enabled)
                    }
                    if failure.kind == .privacy { sourceFiles }
                    Text("Running app").font(.headline)
                    Text(identity.bundleURL.path).font(.caption.monospaced()).textSelection(.enabled)
                    Text(identity.signingDescription).font(.caption).foregroundStyle(.secondary)
                    if identity.signing != .certificate {
                        Text("This build has no verified certificate identity. Rebuilding may require access approval again.")
                            .font(.callout).foregroundStyle(OxidePalette.amber)
                    }
                    if let requestedAt, let review, review.checkedAt >= requestedAt, !isChecking {
                        Text("Last checked \(review.checkedAt.formatted(date: .omitted, time: .standard))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 12)
                .accessibilityElement(children: .contain)
            }
        }
        .accessibilityElement(children: .contain)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            guard recheckOnReturn, !isChecking, canVerify else { return }
            recheckOnReturn = false
            checkAccess()
        }
    }

    @ViewBuilder private var verificationStatus: some View {
        switch verification {
        case .waiting:
            Text("Return here after granting access. We'll check again.")
        case .checking:
            HStack { ProgressView().controlSize(.small); Text("Checking the settings source…") }
        case .readable:
            Label("Preferences are readable. Nothing has been saved.", systemImage: "checkmark.circle.fill")
                .foregroundStyle(OxidePalette.green)
        case .empty:
            Text("No supported preferences found. Nothing to save yet.")
        case .blocked:
            Text(failure.kind == .privacy
                ? "Still blocked. Check the selected app, or restart Nix Me if macOS asked."
                : "Still blocked. Check the file's read permissions.")
                .foregroundStyle(OxidePalette.amber)
        case .otherFailure:
            Text("Couldn't read preferences. See Details below.")
                .foregroundStyle(OxidePalette.amber)
        }
    }

    private func checkAccess() {
        guard !isChecking, canVerify else { return }
        requestedAt = Date()
        verify()
    }

    private func openPrivacy() {
        // These deep links vary across macOS releases; retain a useful manual fallback.
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
        if NSWorkspace.shared.open(url) {
            recheckOnReturn = true
            settingsError = nil
        } else {
            settingsError = "Open System Settings > Privacy & Security > Full Disk Access."
        }
    }

    private var sourceFiles: some View {
        ForEach(application.exportableSettings) { setting in
            Text(setting.source).font(.caption.monospaced()).foregroundStyle(.secondary)
            if setting.source.hasPrefix("/") || setting.source.hasPrefix("~/") {
                Button("Show Source in Finder", systemImage: "folder") {
                    NSWorkspace.shared.activateFileViewerSelecting([
                        URL(fileURLWithPath: (setting.source as NSString).expandingTildeInPath)
                    ])
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline).foregroundStyle(OxidePalette.green).accessibilityAddTraits(.isHeader)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(16)
        .background(OxidePalette.panel).overlay(Rectangle().stroke(OxidePalette.border))
        .accessibilityElement(children: .contain)
    }
}
