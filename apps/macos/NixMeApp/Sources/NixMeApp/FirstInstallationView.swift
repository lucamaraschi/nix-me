import AppKit
import SwiftUI
import UniformTypeIdentifiers

private typealias InstallerPalette = OxidePalette

struct FirstInstallationView: View {
    @StateObject private var installer = FirstInstallationStore()
    @State private var expandedPhases: Set<FirstInstallationPhase> = []
    @State private var expandedPackageGroups: Set<String> = []
    @State private var diagnosticExportMessage: String?
    let keepsMacAwake: Bool
    let openDashboard: () -> Void

    var body: some View {
        ZStack {
            InstallerGridBackground()
            VStack(spacing: 0) {
                header
                Rectangle().fill(InstallerPalette.border).frame(height: 1)
                HStack(spacing: 0) {
                    stepRail
                    Rectangle().fill(InstallerPalette.border).frame(width: 1)
                    content.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                if installer.isTerminalVisible {
                    Rectangle().fill(InstallerPalette.green.opacity(0.45)).frame(height: 1)
                    terminal.transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .preferredColorScheme(.dark)
        .tint(InstallerPalette.green)
        .animation(.easeInOut(duration: 0.2), value: installer.isTerminalVisible)
    }

    private var header: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 5).fill(InstallerPalette.green.opacity(0.12))
                RoundedRectangle(cornerRadius: 5).stroke(InstallerPalette.green.opacity(0.55))
                Image(systemName: "square.3.layers.3d.top.filled")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(InstallerPalette.green)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text("NIX ME // INITIALIZE")
                    .font(.system(.headline, design: .monospaced, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(InstallerPalette.primary)
                Text("Declarative workstation bootstrap")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(InstallerPalette.secondary)
            }
            Spacer(minLength: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text("CONFIGURATION CHECKOUT").installerLabel()
                Text(installer.configurationDirectory.path)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(InstallerPalette.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(width: 360, alignment: .leading)
            Button(action: installer.toggleTerminal) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(installer.isInstalling ? InstallerPalette.green : InstallerPalette.muted)
                        .frame(width: 7, height: 7)
                    Image(systemName: "terminal")
                    Text(installer.isTerminalVisible ? "HIDE TERMINAL" : "OPEN TERMINAL")
                    if !installer.consoleEntries.isEmpty {
                        Text("\(installer.consoleEntries.count)").foregroundStyle(InstallerPalette.green)
                    }
                }
            }
            .buttonStyle(InstallerButtonStyle(variant: .secondary))
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(InstallerPalette.sidebar.opacity(0.96))
    }

    private var stepRail: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("BOOT SEQUENCE").installerLabel().padding(.bottom, 10)
            ForEach(FirstInstallationScreen.allCases, id: \.rawValue) { screen in
                HStack(spacing: 11) {
                    Text(String(format: "%02d", screen.rawValue + 1))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(stepColor(screen))
                        .frame(width: 22, alignment: .leading)
                    Rectangle().fill(stepColor(screen)).frame(width: 2, height: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(screen.title.uppercased())
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(installer.screen.rawValue >= screen.rawValue
                                ? InstallerPalette.primary : InstallerPalette.muted)
                        Text(stepState(screen))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(InstallerPalette.muted)
                    }
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    installer.screen == screen ? InstallerPalette.panel : Color.clear,
                    in: RoundedRectangle(cornerRadius: 4)
                )
            }
            Spacer()
            VStack(alignment: .leading, spacing: 8) {
                statusLine("CHECKOUT", value: installer.setupStatus.checkoutState == .ready ? "READY" : "ATTENTION")
                statusLine("NIX", value: dependencyReady("nix") ? "ONLINE" : "MISSING")
                statusLine("BREW", value: dependencyReady("brew") ? "ONLINE" : "MISSING")
                statusLine("SLEEP", value: keepsMacAwake ? "BLOCKED" : "SYSTEM")
            }
            .padding(12)
            .installerPanel(padding: 0)
            Text("Safe to retry. Existing host definitions are never overwritten.")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(InstallerPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(width: 238, alignment: .leading)
        .background(InstallerPalette.sidebar.opacity(0.92))
    }

    @ViewBuilder
    private var content: some View {
        switch installer.screen {
        case .welcome: welcome
        case .configure: configuration
        case .review: review
        case .install: progress
        case .complete: complete
        }
    }

    private var welcome: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                sectionHeading(
                    index: "00",
                    eyebrow: "SYSTEM READINESS",
                    title: "Bring this Mac under control.",
                    description: "The trusted command-line tools are ready. Choose a saved host or define a new one, then watch every build and activation step from this console."
                )
                awakeNotice
                HStack(spacing: 12) {
                    readinessCard(
                        "Configuration",
                        detail: installer.setupStatus.checkoutState == .ready ? "Checkout connected" : "Needs attention",
                        symbol: "folder.fill",
                        ready: installer.setupStatus.checkoutState == .ready
                    )
                    readinessCard("Nix", detail: dependency("nix"), symbol: "shippingbox.fill", ready: dependencyReady("nix"))
                    readinessCard("Homebrew", detail: dependency("brew"), symbol: "mug.fill", ready: dependencyReady("brew"))
                }
                VStack(alignment: .leading, spacing: 0) {
                    panelHeader("EXECUTION PLAN", detail: "ONE REVIEW / ONE ADMIN APPROVAL")
                    operationRow("01", "Detect", "Read this Mac's hardware and propose a host")
                    operationRow("02", "Compose", "Select reusable profiles instead of individual commands")
                    operationRow("03", "Build", "Resolve and build the complete Nix system as your user")
                    operationRow("04", "Activate", "Request administrator access only after the build succeeds")
                    operationRow("05", "Verify", "Confirm the active generation before reporting success")
                }
                .installerPanel(padding: 0)
                HStack {
                    Label("Commands and output remain available in Open Terminal.", systemImage: "terminal")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(InstallerPalette.secondary)
                    Spacer()
                    Button("BEGIN CONFIGURATION", action: installer.continueFromWelcome)
                        .buttonStyle(InstallerButtonStyle(variant: .primary))
                        .disabled(!installer.setupStatus.isReady)
                }
            }
            .padding(34)
        }
    }

    private var awakeNotice: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: keepsMacAwake ? "bolt.shield.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(keepsMacAwake ? InstallerPalette.green : InstallerPalette.amber)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 5) {
                Text(keepsMacAwake ? "SLEEP PREVENTION ACTIVE" : "SLEEP PREVENTION UNAVAILABLE")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(InstallerPalette.primary)
                Text(keepsMacAwake
                    ? "Nix Me will keep this Mac and its display awake until setup finishes or the app closes. Keep the lid open and connect power for long installations."
                    : "Keep this Mac awake manually until setup finishes. Keep the lid open and connect power for long installations.")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(InstallerPalette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .installerPanel()
    }

    private var configuration: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                sectionHeading(
                    index: "01",
                    eyebrow: "HOST TARGET",
                    title: "Choose the desired machine state.",
                    description: "Apply a host already defined by this checkout, or create a new host from the detected hardware."
                )
                HStack {
                    Text("SAVED MACHINES").installerLabel()
                    Spacer()
                    Text("DETECTED / \(installer.detectedHostname)").installerLabel()
                }
                if installer.availableMachines.isEmpty {
                    Label("No Darwin machine configurations were found in flake.nix.", systemImage: "tray")
                        .foregroundStyle(InstallerPalette.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .installerPanel()
                } else {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(installer.availableMachines) { machine in machineCard(machine) }
                    }
                }
                createMachineCard
                if let machine = installer.selectedExistingMachine {
                    VStack(alignment: .leading, spacing: 0) {
                        panelHeader("SELECTED HOST", detail: "DECLARATIVE / UNCHANGED")
                        reviewRow("Configuration", value: machine.id)
                        reviewRow("Computer name", value: machine.machineName)
                        reviewRow("Hardware", value: machineTypeLabel(machine.machineType))
                        reviewRow("User", value: machine.username)
                        reviewRow("Profiles", value: profileSummary(for: machine.profiles))
                    }
                    .installerPanel(padding: 0)
                } else if installer.isCreatingNewMachine {
                    newMachineConfiguration
                }
                if let validation = installer.validationMessage {
                    inlineNotice(validation, color: InstallerPalette.amber, symbol: "exclamationmark.triangle.fill")
                }
                HStack {
                    Button("BACK", action: installer.goBack)
                        .buttonStyle(InstallerButtonStyle(variant: .secondary))
                    Spacer()
                    Button("REVIEW CONFIGURATION", action: installer.continueFromConfiguration)
                        .buttonStyle(InstallerButtonStyle(variant: .primary))
                        .disabled(installer.validationMessage != nil)
                }
            }
            .padding(34)
        }
    }

    private var newMachineConfiguration: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 14) {
                panelHeader("NEW HOST", detail: "LOCAL MACHINE DEFINITION")
                HStack(spacing: 12) {
                    installerField("HOSTNAME", text: $installer.hostname, placeholder: "my-mac")
                    installerField("DISPLAY NAME", text: $installer.machineName, placeholder: "My Mac")
                    installerField("USERNAME", text: $installer.username, placeholder: "username")
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("HARDWARE").installerLabel()
                    Picker("Hardware", selection: $installer.machineType) {
                        Text("MacBook").tag("macbook")
                        Text("MacBook Pro").tag("macbook-pro")
                        Text("Mac mini").tag("macmini")
                        Text("Virtual machine").tag("vm")
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }
            }
            .installerPanel()
            VStack(alignment: .leading, spacing: 12) {
                Text("PROFILE MODULES").installerLabel()
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(FirstInstallationStore.profiles) { profile in profileCard(profile) }
                }
            }
            Toggle(isOn: $installer.appStateEnabled) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("MANAGE APPLICATION STATE")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(InstallerPalette.primary)
                    Text("Apply reviewed portable settings; credentials and private data stay local.")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(InstallerPalette.secondary)
                }
            }
            .toggleStyle(.switch)
            .padding(16)
            .installerPanel(padding: 0)
        }
    }

    private var review: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                sectionHeading(
                    index: "02",
                    eyebrow: "PRE-FLIGHT REVIEW",
                    title: "Confirm the deployment target.",
                    description: installer.configurationExists
                        ? "This saved host definition will be applied unchanged, even if this Mac currently has a different name."
                        : "Nix Me will write this host definition, build the system, request approval, and verify the active generation."
                )
                if let resumeMessage = installer.resumeMessage {
                    inlineNotice(resumeMessage, color: InstallerPalette.amber, symbol: "arrow.clockwise.circle.fill")
                }
                VStack(alignment: .leading, spacing: 0) {
                    panelHeader("DEPLOYMENT MANIFEST", detail: installer.configurationExists ? "EXISTING HOST" : "NEW HOST")
                    reviewRow(installer.configurationExists ? "Machine configuration" : "Hostname", value: installer.hostname)
                    reviewRow("Mac", value: installer.machineName)
                    reviewRow("Hardware", value: machineTypeLabel)
                    reviewRow("User", value: installer.username)
                    reviewRow("Profiles", value: profileSummary)
                    if !installer.configurationExists {
                        reviewRow("Application settings", value: installer.appStateEnabled ? "Managed" : "Not managed")
                    }
                }
                .installerPanel(padding: 0)
                HStack(spacing: 14) {
                    Image(systemName: "lock.shield").font(.title2).foregroundStyle(InstallerPalette.green)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("LEAST-PRIVILEGE ACTIVATION").installerLabel(color: InstallerPalette.green)
                        Text("The build runs as \(installer.username). macOS asks for administrator approval only when the completed generation is ready to activate.")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(InstallerPalette.secondary)
                    }
                }
                .installerPanel()
                HStack {
                    Button("BACK", action: installer.goBack)
                        .buttonStyle(InstallerButtonStyle(variant: .secondary))
                    Spacer()
                    Button(installer.resumeMessage != nil
                        ? "RETRY DEPLOYMENT"
                        : installer.configurationExists ? "APPLY CONFIGURATION" : "CREATE + APPLY") {
                        Task { await installer.install() }
                    }
                    .buttonStyle(InstallerButtonStyle(variant: .primary))
                }
            }
            .padding(34)
        }
    }

    private var progress: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 20) {
                sectionHeading(
                    index: "03",
                    eyebrow: deploymentEyebrow,
                    title: deploymentTitle,
                    description: installer.errorMessage ?? installer.phaseMessage
                )
                Spacer()
                VStack(alignment: .trailing, spacing: 5) {
                    Text("\(Int(installer.overallProgress * 100))%")
                        .font(.system(size: 22, weight: .medium, design: .monospaced))
                        .foregroundStyle(installer.errorMessage == nil && installer.runState != .stopped
                            ? InstallerPalette.green : InstallerPalette.amber)
                    Text("OVERALL PROGRESS").installerLabel()
                }
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle().fill(InstallerPalette.border)
                    Rectangle()
                        .fill(installer.errorMessage == nil ? InstallerPalette.green : InstallerPalette.amber)
                        .frame(width: geometry.size.width * installer.overallProgress)
                }
            }
            .frame(height: 5)
            installationControls
            phaseTimelinePanel
            if let errorMessage = installer.errorMessage {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("DEPLOYMENT FAILED", systemImage: "exclamationmark.octagon.fill")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(InstallerPalette.amber)
                        Spacer()
                        Button("EXPORT DIAGNOSTIC", action: exportDiagnostic)
                            .buttonStyle(InstallerButtonStyle(variant: .secondary))
                    }
                    Text(errorMessage)
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(InstallerPalette.primary)
                    Text("The failing block remains expanded. Export the complete Markdown diagnostic for an LLM or maintainer, fix the issue, then retry safely.")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(InstallerPalette.secondary)
                    if let diagnosticExportMessage {
                        Text(diagnosticExportMessage)
                            .installerLabel(color: diagnosticExportMessage.hasPrefix("SAVED")
                                ? InstallerPalette.green : InstallerPalette.amber)
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .installerPanel(border: InstallerPalette.amber.opacity(0.55))
            }
            if installer.runState == .stopped {
                VStack(alignment: .leading, spacing: 8) {
                    Label("INSTALLATION STOPPED", systemImage: "stop.circle.fill")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(InstallerPalette.amber)
                    Text("No further operation was started. Review the execution log, then restart when ready; completed Nix store work will be reused.")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(InstallerPalette.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .installerPanel(border: InstallerPalette.amber.opacity(0.55))
            }
                HStack {
                    Button(installer.isTerminalVisible ? "HIDE EXECUTION LOG" : "OPEN EXECUTION LOG", action: installer.toggleTerminal)
                        .buttonStyle(InstallerButtonStyle(variant: .secondary))
                    Spacer()
                    if installer.errorMessage != nil || installer.runState == .stopped {
                        Button("BACK TO REVIEW", action: installer.goBack)
                            .buttonStyle(InstallerButtonStyle(variant: .secondary))
                        Button("RETRY", action: { Task { await installer.install() } })
                            .buttonStyle(InstallerButtonStyle(variant: .primary))
                    }
                }
            }
            .padding(30)
        }
    }

    private var installationControls: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(controlColor)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(controlTitle)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(InstallerPalette.primary)
                Text(controlDetail)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(InstallerPalette.secondary)
            }
            Spacer()
            if installer.isInstalling {
                Button(installer.runState.isPaused ? "RESUME" : "PAUSE AFTER CURRENT STEP") {
                    installer.toggleInstallationPause()
                }
                .buttonStyle(OxideButtonStyle(variant: .secondary))
                .disabled(!installer.canPauseInstallation)

                Button("STOP INSTALLATION", action: installer.stopInstallation)
                    .buttonStyle(OxideButtonStyle(variant: .destructive))
                    .disabled(!installer.canStopInstallation)
            }
        }
        .installerPanel(padding: 12, border: controlColor.opacity(0.42))
    }

    private var phaseTimelinePanel: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("DEPLOYMENT RUN")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(InstallerPalette.primary)
                    Text("THE ACTIVE BLOCK EXPANDS; COMPLETED BLOCKS COLLAPSE AUTOMATICALLY")
                        .installerLabel()
                }
                Spacer()
                packageCounter(.nix, symbol: "shippingbox.fill")
                    .frame(width: 150)
                packageCounter(.homebrew, symbol: "mug.fill")
                    .frame(width: 150)
                packageCounter(.macAppStore, symbol: "apple.logo")
                    .frame(width: 150)
            }
            .padding(14)
            .background(InstallerPalette.panelRaised.opacity(0.65))
            .overlay(alignment: .bottom) { Rectangle().fill(InstallerPalette.border).frame(height: 1) }
            ForEach(FirstInstallationPhase.allCases, id: \.rawValue) { phase in
                phaseBlock(phase)
                if phase != .verification { Rectangle().fill(InstallerPalette.border).frame(height: 1) }
            }
        }
        .installerPanel(padding: 0)
    }

    private func phaseBlock(_ phase: FirstInstallationPhase) -> some View {
        let steps = installer.stepActivities.filter { $0.phase == phase }.sorted { $0.sequence < $1.sequence }
        let packages = installer.packageActivities.filter { $0.phase == phase }.sorted { $0.sequence < $1.sequence }
        let expanded = isPhaseExpanded(phase)
        return VStack(spacing: 0) {
            Button {
                guard phase != installer.phase else { return }
                if expandedPhases.contains(phase) {
                    expandedPhases.remove(phase)
                } else {
                    expandedPhases.insert(phase)
                }
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        Rectangle().fill(phaseColor(phase).opacity(0.12))
                        Image(systemName: phaseSymbol(phase))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(phaseColor(phase))
                    }
                    .frame(width: 30, height: 30)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(phase.title.uppercased())
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(phase.rawValue <= installer.phase.rawValue
                                ? InstallerPalette.primary : InstallerPalette.muted)
                        if phase == installer.phase {
                            Text(installer.phaseMessage)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(InstallerPalette.secondary)
                                .lineLimit(1)
                        } else {
                            Text("\(steps.count) ACTIONS / \(packages.count) PACKAGES")
                                .installerLabel()
                        }
                    }
                    Spacer()
                    Text(phaseState(phase))
                        .installerLabel(color: phaseColor(phase))
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(InstallerPalette.muted)
                }
                .contentShape(Rectangle())
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)

            if expanded {
                phaseDetails(phase, steps: steps, packages: packages)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.18), value: expanded)
    }

    @ViewBuilder
    private func phaseDetails(
        _ phase: FirstInstallationPhase,
        steps: [InstallerStepActivity],
        packages: [InstallerPackageActivity]
    ) -> some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(InstallerPalette.border).frame(height: 1)
            if steps.isEmpty && packages.isEmpty {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small).opacity(phase == installer.phase ? 1 : 0)
                    Text(phase == installer.phase
                        ? "Waiting for the first operation in this block…"
                        : "No operations were required for this block.")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(InstallerPalette.secondary)
                }
                .padding(16)
            }
            ForEach(steps) { activity in
                stepRow(activity)
                Rectangle().fill(InstallerPalette.border.opacity(0.55)).frame(height: 1)
            }
            ForEach(ApplyPackageManager.allCases, id: \.rawValue) { manager in
                let managedPackages = packages.filter { $0.manager == manager }
                if !managedPackages.isEmpty {
                    packageGroup(manager, phase: phase, packages: managedPackages)
                }
            }
        }
        .background(InstallerPalette.background.opacity(0.48))
    }

    private var terminal: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "terminal.fill").foregroundStyle(InstallerPalette.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("EXECUTION LOG // THIS RUN")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(InstallerPalette.primary)
                    Text("COMMANDS AND USEFUL OUTPUT // FULL RAW PROTOCOL IN EXPORT")
                        .installerLabel()
                }
                if installer.isInstalling {
                    Text("LIVE")
                        .installerLabel(color: InstallerPalette.green)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .overlay(Rectangle().stroke(InstallerPalette.green.opacity(0.5)))
                }
                Spacer()
                Button("EXPORT .MD", action: exportDiagnostic)
                    .buttonStyle(InstallerButtonStyle(variant: .ghost))
                Button("COPY ALL", action: copyTerminal)
                    .buttonStyle(InstallerButtonStyle(variant: .ghost))
                Button(action: installer.toggleTerminal) { Image(systemName: "xmark") }
                    .buttonStyle(InstallerButtonStyle(variant: .ghost))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(InstallerPalette.sidebar)
            Rectangle().fill(InstallerPalette.border).frame(height: 1)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        if installer.consoleEntries.isEmpty {
                            Text("terminal ready; commands appear when deployment starts")
                                .foregroundStyle(InstallerPalette.muted)
                        }
                        ForEach(installer.consoleEntries) { entry in
                            terminalRow(entry).id(entry.id)
                        }
                        Color.clear.frame(height: 1).id("installer-terminal-bottom")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                }
                .onChange(of: installer.consoleEntries.last?.id) { _, _ in
                    DispatchQueue.main.async {
                        proxy.scrollTo("installer-terminal-bottom", anchor: .bottom)
                    }
                }
            }
        }
        .font(.system(size: 11, design: .monospaced))
        .frame(height: 250)
        .background(InstallerPalette.terminal)
    }

    private var complete: some View {
        VStack(spacing: 24) {
            Spacer()
            ZStack {
                Rectangle().fill(InstallerPalette.green.opacity(0.12))
                Rectangle().stroke(InstallerPalette.green.opacity(0.6))
                Image(systemName: "checkmark")
                    .font(.system(size: 38, weight: .light))
                    .foregroundStyle(InstallerPalette.green)
            }
            .frame(width: 88, height: 88)
            Text("SYSTEM CONVERGED").installerLabel(color: InstallerPalette.green)
            Text("This Mac is managed.")
                .font(.system(size: 34, weight: .medium, design: .rounded))
                .foregroundStyle(InstallerPalette.primary)
            Text("The configuration was built, activated, and verified. The managed Nix Me app is available in Applications.")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(InstallerPalette.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 650)
            HStack(spacing: 10) {
                Button("VIEW EXECUTION LOG", action: installer.toggleTerminal)
                    .buttonStyle(InstallerButtonStyle(variant: .secondary))
                Button("OPEN NIX ME", action: openDashboard)
                    .buttonStyle(InstallerButtonStyle(variant: .primary))
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(36)
    }

    private func sectionHeading(index: String, eyebrow: String, title: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                Text(index).foregroundStyle(InstallerPalette.green)
                Rectangle().fill(InstallerPalette.green).frame(width: 26, height: 1)
                Text(eyebrow).foregroundStyle(InstallerPalette.secondary)
            }
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .tracking(0.9)
            Text(title)
                .font(.system(size: 30, weight: .medium, design: .rounded))
                .foregroundStyle(InstallerPalette.primary)
            Text(description)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(InstallerPalette.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 780, alignment: .leading)
        }
    }

    private func readinessCard(_ title: String, detail: String, symbol: String, ready: Bool) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(ready ? InstallerPalette.green : InstallerPalette.amber)
                Spacer()
                Text(ready ? "ONLINE" : "CHECK")
                    .installerLabel(color: ready ? InstallerPalette.green : InstallerPalette.amber)
            }
            Text(title.uppercased())
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(InstallerPalette.primary)
            Text(detail)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(InstallerPalette.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 105, alignment: .leading)
        .installerPanel(border: ready ? InstallerPalette.green.opacity(0.28) : InstallerPalette.amber.opacity(0.4))
    }

    private func operationRow(_ number: String, _ title: String, _ detail: String) -> some View {
        HStack(spacing: 14) {
            Text(number).foregroundStyle(InstallerPalette.green).frame(width: 24)
            Text(title.uppercased())
                .foregroundStyle(InstallerPalette.primary)
                .frame(width: 90, alignment: .leading)
            Text(detail).foregroundStyle(InstallerPalette.secondary)
            Spacer()
        }
        .font(.system(size: 11, weight: .semibold, design: .monospaced))
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .overlay(alignment: .bottom) { Rectangle().fill(InstallerPalette.border).frame(height: 1) }
    }

    private func machineCard(_ machine: InstallationMachineConfiguration) -> some View {
        let selected = installer.selectedExistingMachine?.id == machine.id
        let suggested = machine.id == installer.detectedHostname
        return Button { installer.selectExistingMachine(machine) } label: {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    Image(systemName: selected ? "checkmark.square.fill" : "desktopcomputer")
                        .font(.title3)
                        .foregroundStyle(selected ? InstallerPalette.green : InstallerPalette.secondary)
                    Spacer()
                    if suggested { Text("HOST MATCH").installerLabel(color: InstallerPalette.green) }
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(machine.machineName)
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundStyle(InstallerPalette.primary)
                    Text(machine.id)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(InstallerPalette.secondary)
                }
                Text("\(machineTypeLabel(machine.machineType).uppercased()) / \(profileSummary(for: machine.profiles).uppercased())")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(InstallerPalette.muted)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, minHeight: 102, alignment: .topLeading)
            .installerPanel(border: selected ? InstallerPalette.green : InstallerPalette.border)
        }
        .buttonStyle(.plain)
    }

    private var createMachineCard: some View {
        let selected = installer.isCreatingNewMachine
        return Button(action: installer.selectNewMachine) {
            HStack(spacing: 13) {
                Image(systemName: selected ? "checkmark.square.fill" : "plus.square")
                    .font(.title3)
                    .foregroundStyle(InstallerPalette.green)
                VStack(alignment: .leading, spacing: 3) {
                    Text("CREATE A NEW MACHINE CONFIGURATION")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(InstallerPalette.primary)
                    Text("Start from detected hardware, then compose the host from reusable profiles.")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(InstallerPalette.secondary)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .installerPanel(border: selected ? InstallerPalette.green : InstallerPalette.border)
        }
        .buttonStyle(.plain)
    }

    private func profileCard(_ profile: InstallationProfile) -> some View {
        let selected = installer.selectedProfiles.contains(profile.id)
        return Button { installer.toggleProfile(profile) } label: {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: profile.symbol)
                    .font(.title3)
                    .foregroundStyle(selected ? InstallerPalette.green : InstallerPalette.secondary)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 4) {
                    Text(profile.name.uppercased())
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(InstallerPalette.primary)
                    Text(profile.summary)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(InstallerPalette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: selected ? "checkmark.square.fill" : "square")
                    .foregroundStyle(selected ? InstallerPalette.green : InstallerPalette.muted)
            }
            .frame(maxWidth: .infinity, minHeight: 70, alignment: .topLeading)
            .installerPanel(border: selected ? InstallerPalette.green.opacity(0.7) : InstallerPalette.border)
        }
        .buttonStyle(.plain)
    }

    private func installerField(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label).installerLabel()
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(.body, design: .monospaced))
                .padding(.horizontal, 11)
                .padding(.vertical, 9)
                .background(InstallerPalette.background.opacity(0.75))
                .overlay(Rectangle().stroke(InstallerPalette.borderStrong))
        }
        .frame(maxWidth: .infinity)
    }

    private func panelHeader(_ title: String, detail: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(InstallerPalette.primary)
            Spacer()
            Text(detail).installerLabel()
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 11)
        .background(InstallerPalette.panelRaised.opacity(0.65))
        .overlay(alignment: .bottom) { Rectangle().fill(InstallerPalette.border).frame(height: 1) }
    }

    private func reviewRow(_ label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 20) {
            Text(label.uppercased()).installerLabel().frame(width: 180, alignment: .leading)
            Text(value)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(InstallerPalette.primary)
                .textSelection(.enabled)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) { Rectangle().fill(InstallerPalette.border).frame(height: 1) }
    }

    private func inlineNotice(_ message: String, color: Color, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).foregroundStyle(color)
            Text(message)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(InstallerPalette.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .installerPanel(border: color.opacity(0.5))
    }

    private func packageCounter(_ manager: ApplyPackageManager, symbol: String) -> some View {
        let packages = installer.packageActivities.filter { $0.manager == manager }
        let completed = packages.filter { $0.state == .complete }.count
        return HStack(spacing: 11) {
            Image(systemName: symbol)
                .foregroundStyle(packageManagerColor(manager))
            VStack(alignment: .leading, spacing: 2) {
                Text(manager.title.uppercased()).installerLabel()
                Text(packages.isEmpty ? "WAITING" : "\(completed) / \(packages.count) DONE")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(InstallerPalette.primary)
            }
            Spacer()
        }
        .padding(12)
        .background(InstallerPalette.background.opacity(0.55))
        .overlay(Rectangle().stroke(InstallerPalette.border))
    }

    private func packageRow(_ activity: InstallerPackageActivity) -> some View {
        HStack(alignment: .center, spacing: 11) {
            Rectangle()
                .fill(packageManagerColor(activity.manager))
                .frame(width: 3, height: activity.fractionCompleted == nil ? 30 : 38)
            VStack(alignment: .leading, spacing: 3) {
                Text(activity.name)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(InstallerPalette.primary)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(activity.manager.title.uppercased()).installerLabel()
                    if let fraction = activity.fractionCompleted, activity.state != .complete {
                        ProgressView(value: fraction)
                            .progressViewStyle(.linear)
                            .tint(packageManagerColor(activity.manager))
                            .frame(maxWidth: 190)
                        Text("\(Int(fraction * 100))%").installerLabel()
                    }
                }
            }
            Spacer()
            Text(activity.state.title.uppercased())
                .installerLabel(color: packageStateColor(activity.state))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .help(activity.detail)
    }

    private func packageGroup(
        _ manager: ApplyPackageManager,
        phase: FirstInstallationPhase,
        packages: [InstallerPackageActivity]
    ) -> some View {
        let active = packages.filter { $0.state != .complete && $0.state != .queued }
        let queued = packages.filter { $0.state == .queued }
        let completed = packages.filter { $0.state == .complete }
        let key = "\(phase.rawValue):\(manager.rawValue)"
        let expanded = expandedPackageGroups.contains(key)
        let visibleCompleted = expanded ? completed : Array(completed.suffix(3))

        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: packageManagerSymbol(manager))
                    .foregroundStyle(packageManagerColor(manager))
                Text(manager.title.uppercased())
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(InstallerPalette.primary)
                Text("\(completed.count) COMPLETE")
                    .installerLabel(color: InstallerPalette.green)
                if !active.isEmpty {
                    Text("\(active.count) ACTIVE")
                        .installerLabel(color: InstallerPalette.amber)
                }
                if !queued.isEmpty {
                    Text("\(queued.count) QUEUED")
                        .installerLabel()
                }
                Spacer()
                if completed.count > 3 {
                    Button(expanded ? "COLLAPSE HISTORY" : "SHOW \(completed.count) COMPLETED") {
                        if expanded {
                            expandedPackageGroups.remove(key)
                        } else {
                            expandedPackageGroups.insert(key)
                        }
                    }
                    .buttonStyle(InstallerButtonStyle(variant: .ghost))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(InstallerPalette.panelRaised.opacity(0.45))

            ForEach(active) { activity in
                packageRow(activity)
                Rectangle().fill(InstallerPalette.border.opacity(0.55)).frame(height: 1)
            }
            ForEach(visibleCompleted) { activity in
                packageRow(activity)
                Rectangle().fill(InstallerPalette.border.opacity(0.55)).frame(height: 1)
            }
        }
    }

    private func stepRow(_ activity: InstallerStepActivity) -> some View {
        HStack(spacing: 11) {
            Image(systemName: activitySymbol(activity.state))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(activityColor(activity.state))
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                Text(activity.title)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(InstallerPalette.primary)
                Text(activity.detail)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(InstallerPalette.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Text(activity.state.title)
                .installerLabel(color: activityColor(activity.state))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .help(activity.detail)
    }

    private func terminalRow(_ entry: InstallerConsoleEntry) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Text(entry.timestamp.formatted(date: .omitted, time: .standard))
                .foregroundStyle(InstallerPalette.muted)
                .frame(width: 72, alignment: .leading)
            Text(terminalPrefix(entry.kind))
                .foregroundStyle(terminalColor(entry.kind))
                .frame(width: 16, alignment: .leading)
            Text(entry.message)
                .foregroundStyle(terminalColor(entry.kind))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func copyTerminal() {
        let contents = installer.consoleEntries.map { entry in
            "[\(entry.timestamp.formatted(date: .omitted, time: .standard))] \(terminalPrefix(entry.kind)) \(entry.message)"
        }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(contents, forType: .string)
    }

    private func exportDiagnostic() {
        let panel = NSSavePanel()
        panel.title = "Export Nix Me Diagnostic"
        panel.message = "Save the complete installer timeline and raw command output as Markdown. Review local paths and usernames before sharing."
        panel.nameFieldStringValue = "nix-me-\(installer.hostname)-diagnostic.md"
        panel.canCreateDirectories = true
        if let markdown = UTType(filenameExtension: "md") {
            panel.allowedContentTypes = [markdown]
        }
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            try installer.diagnosticReport().write(to: destination, atomically: true, encoding: .utf8)
            diagnosticExportMessage = "SAVED // \(destination.path)"
        } catch {
            diagnosticExportMessage = "EXPORT FAILED // \(error.localizedDescription)"
        }
    }

    private func terminalPrefix(_ kind: InstallerConsoleEntryKind) -> String {
        switch kind {
        case .command: "$"
        case .output: "│"
        case .status: "::"
        case .error: "!!"
        }
    }

    private func terminalColor(_ kind: InstallerConsoleEntryKind) -> Color {
        switch kind {
        case .command: InstallerPalette.green
        case .output: InstallerPalette.primary.opacity(0.86)
        case .status: InstallerPalette.cyan
        case .error: InstallerPalette.amber
        }
    }

    private func statusLine(_ name: String, value: String) -> some View {
        HStack {
            Text(name)
            Spacer()
            Text(value)
                .foregroundStyle(value == "READY" || value == "ONLINE" ? InstallerPalette.green : InstallerPalette.amber)
        }
        .font(.system(size: 9, weight: .semibold, design: .monospaced))
        .foregroundStyle(InstallerPalette.secondary)
    }

    private func phaseState(_ phase: FirstInstallationPhase) -> String {
        if phase.rawValue < installer.phase.rawValue || installer.screen == .complete { return "COMPLETE" }
        if phase == installer.phase {
            if installer.errorMessage != nil { return "FAILED" }
            if installer.runState == .stopped { return "STOPPED" }
            if installer.runState.isPaused { return "PAUSED" }
            return installer.isInstalling ? "RUNNING" : "READY"
        }
        return "QUEUED"
    }

    private func phaseSymbol(_ phase: FirstInstallationPhase) -> String {
        if phase.rawValue < installer.phase.rawValue || installer.screen == .complete { return "checkmark" }
        if installer.errorMessage != nil && phase == installer.phase { return "exclamationmark" }
        if installer.runState == .stopped && phase == installer.phase { return "stop.fill" }
        if installer.runState.isPaused && phase == installer.phase { return "pause.fill" }
        return phase.symbol
    }

    private func phaseColor(_ phase: FirstInstallationPhase) -> Color {
        if installer.errorMessage != nil && phase == installer.phase { return InstallerPalette.amber }
        if installer.runState == .stopped && phase == installer.phase { return InstallerPalette.amber }
        if phase.rawValue <= installer.phase.rawValue { return InstallerPalette.green }
        return InstallerPalette.muted
    }

    private func isPhaseExpanded(_ phase: FirstInstallationPhase) -> Bool {
        phase == installer.phase || expandedPhases.contains(phase)
    }

    private func activitySymbol(_ state: InstallerActivityState) -> String {
        switch state {
        case .queued: "circle"
        case .running: "arrow.right"
        case .complete: "checkmark"
        case .failed: "exclamationmark"
        case .cancelled: "stop.fill"
        }
    }

    private func activityColor(_ state: InstallerActivityState) -> Color {
        switch state {
        case .queued: InstallerPalette.muted
        case .running: InstallerPalette.cyan
        case .complete: InstallerPalette.green
        case .failed: InstallerPalette.amber
        case .cancelled: InstallerPalette.amber
        }
    }

    private func packageStateColor(_ state: ApplyPackageState) -> Color {
        switch state {
        case .queued: InstallerPalette.muted
        case .downloading: InstallerPalette.cyan
        case .building, .installing: InstallerPalette.amber
        case .complete: InstallerPalette.green
        case .failed: InstallerPalette.amber
        case .cancelled: InstallerPalette.amber
        }
    }

    private func packageManagerColor(_ manager: ApplyPackageManager) -> Color {
        switch manager {
        case .nix: InstallerPalette.cyan
        case .homebrew: InstallerPalette.amber
        case .macAppStore: InstallerPalette.green
        }
    }

    private func packageManagerSymbol(_ manager: ApplyPackageManager) -> String {
        switch manager {
        case .nix: "shippingbox.fill"
        case .homebrew: "mug.fill"
        case .macAppStore: "apple.logo"
        }
    }

    private var deploymentEyebrow: String {
        if installer.errorMessage != nil { return "DEPLOYMENT HALTED" }
        if installer.runState == .stopped { return "DEPLOYMENT STOPPED" }
        if installer.runState.isPaused { return "DEPLOYMENT PAUSED" }
        return "DEPLOYMENT ACTIVE"
    }

    private var deploymentTitle: String {
        if installer.errorMessage != nil { return "Setup needs attention." }
        if installer.runState == .stopped { return "Installation stopped safely." }
        if installer.runState.isPaused { return "Waiting at a safe boundary." }
        return "Applying the desired state."
    }

    private var controlTitle: String {
        return switch installer.runState {
        case .pauseRequested: "PAUSE REQUESTED"
        case .paused: "INSTALLATION PAUSED"
        case .stopping: "STOPPING INSTALLATION"
        case .stopped: "INSTALLATION STOPPED"
        case .idle: "INSTALLATION CONTROLS READY"
        case .running where [.activation, .verification].contains(installer.phase): "CRITICAL SYSTEM STEP"
        case .running: "INSTALLATION RUNNING"
        }
    }

    private var controlDetail: String {
        if installer.isInstalling && [.activation, .verification].contains(installer.phase) {
            return "Pause and stop are locked while activation is committed and verified."
        }
        return switch installer.runState {
        case .pauseRequested: "The active operation will finish, then setup will pause before the next system change."
        case .paused: "No new operation will start until you resume."
        case .stopping: "Waiting for the active process to exit and preserve completed work."
        case .stopped: "Completed downloads and Nix store paths remain available for the next run."
        default: "Pause waits for a safe boundary; stop is available until privileged activation begins."
        }
    }

    private var controlColor: Color {
        switch installer.runState {
        case .running: InstallerPalette.green
        case .pauseRequested, .paused, .stopping, .stopped: InstallerPalette.amber
        case .idle: InstallerPalette.muted
        }
    }

    private func dependencyReady(_ command: String) -> Bool {
        installer.setupStatus.dependencies.first(where: { $0.command == command })?.isAvailable == true
    }

    private func dependency(_ command: String) -> String {
        dependencyReady(command) ? "Available" : "Not found"
    }

    private var profileSummary: String { profileSummary(for: Array(installer.selectedProfiles)) }

    private func profileSummary(for ids: [String]) -> String {
        let namesByID = Dictionary(uniqueKeysWithValues: FirstInstallationStore.profiles.map { ($0.id, $0.name) })
        let names = ids.sorted().map { namesByID[$0] ?? $0 }
        return names.isEmpty ? "Minimal base" : names.joined(separator: ", ")
    }

    private var machineTypeLabel: String { machineTypeLabel(installer.machineType) }

    private func machineTypeLabel(_ machineType: String) -> String {
        switch machineType {
        case "macbook-pro": "MacBook Pro"
        case "macmini": "Mac mini"
        case "vm": "Virtual machine"
        default: "MacBook"
        }
    }

    private func stepColor(_ screen: FirstInstallationScreen) -> Color {
        installer.screen.rawValue >= screen.rawValue ? InstallerPalette.green : InstallerPalette.muted
    }

    private func stepState(_ screen: FirstInstallationScreen) -> String {
        if installer.screen.rawValue > screen.rawValue { return "COMPLETE" }
        if installer.screen == screen { return "ACTIVE" }
        return "PENDING"
    }
}

private struct InstallerGridBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [InstallerPalette.background, Color(red: 0.025, green: 0.044, blue: 0.051)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Canvas { context, size in
                var grid = Path()
                stride(from: 0.0, through: size.width, by: 44).forEach { x in
                    grid.move(to: CGPoint(x: x, y: 0))
                    grid.addLine(to: CGPoint(x: x, y: size.height))
                }
                stride(from: 0.0, through: size.height, by: 44).forEach { y in
                    grid.move(to: CGPoint(x: 0, y: y))
                    grid.addLine(to: CGPoint(x: size.width, y: y))
                }
                context.stroke(grid, with: .color(Color.white.opacity(0.018)), lineWidth: 0.5)
            }
        }
        .ignoresSafeArea()
    }
}

private struct InstallerButtonStyle: ButtonStyle {
    enum Variant { case primary, secondary, ghost }
    @Environment(\.isEnabled) private var isEnabled
    let variant: Variant

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .tracking(0.35)
            .foregroundStyle(foreground)
            .padding(.horizontal, variant == .ghost ? 8 : 14)
            .padding(.vertical, variant == .ghost ? 6 : 9)
            .background(background(configuration.isPressed))
            .overlay(Rectangle().stroke(border, lineWidth: variant == .ghost ? 0 : 1))
            .contentShape(Rectangle())
            .opacity(isEnabled ? 1 : 0.4)
    }

    private var foreground: Color {
        variant == .primary ? InstallerPalette.background : InstallerPalette.primary
    }

    private var border: Color {
        switch variant {
        case .primary: InstallerPalette.green
        case .secondary: InstallerPalette.borderStrong
        case .ghost: .clear
        }
    }

    private func background(_ pressed: Bool) -> Color {
        switch variant {
        case .primary: InstallerPalette.green.opacity(pressed ? 0.72 : 1)
        case .secondary: InstallerPalette.panelRaised.opacity(pressed ? 1 : 0.72)
        case .ghost: pressed ? InstallerPalette.panelRaised : .clear
        }
    }
}

private extension View {
    func installerPanel(padding: CGFloat = 16, border: Color = InstallerPalette.border) -> some View {
        self
            .padding(padding)
            .background(InstallerPalette.panel.opacity(0.72))
            .overlay(Rectangle().stroke(border))
    }

    func installerLabel(color: Color = InstallerPalette.muted) -> some View {
        self
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .tracking(0.7)
            .foregroundStyle(color)
    }
}
