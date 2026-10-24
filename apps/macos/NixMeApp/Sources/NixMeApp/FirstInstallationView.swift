import SwiftUI

struct FirstInstallationView: View {
    @StateObject private var installer = FirstInstallationStore()
    let openDashboard: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                stepRail
                Divider()
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "square.3.layers.3d.top.filled")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.cyan)
                .frame(width: 48, height: 48)
                .background(.cyan.opacity(0.12), in: RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 2) {
                Text("Set up Nix Me")
                    .font(.title2.weight(.semibold))
                Text("Choose what this Mac needs. Nix Me will build and verify the result.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(installer.configurationDirectory.path)
                .font(.caption.monospaced())
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 18)
    }

    private var stepRail: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(FirstInstallationScreen.allCases, id: \.rawValue) { screen in
                HStack(spacing: 10) {
                    Image(systemName: stepSymbol(screen))
                        .foregroundStyle(stepColor(screen))
                        .frame(width: 20)
                    Text(screen.title)
                        .fontWeight(installer.screen == screen ? .semibold : .regular)
                        .foregroundStyle(installer.screen.rawValue >= screen.rawValue ? .primary : .tertiary)
                }
                .padding(.vertical, 7)
            }
            Spacer()
            Text("You can safely retry after an interruption. Existing machine definitions are never overwritten.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(width: 225, alignment: .leading)
        .background(.quaternary.opacity(0.35))
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
        VStack(alignment: .leading, spacing: 24) {
            Text("Your Mac is ready to configure")
                .font(.largeTitle.weight(.semibold))
            Text("The terminal has finished preparing the configuration checkout and build tools. From here, the app handles the rest with one review and one standard administrator approval.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 14) {
                readinessCard("Configuration", detail: installer.setupStatus.checkoutState == .ready ? "Connected" : "Needs attention", symbol: "folder.fill", ready: installer.setupStatus.checkoutState == .ready)
                readinessCard("Nix", detail: dependency("nix"), symbol: "shippingbox.fill", ready: dependencyReady("nix"))
                readinessCard("Homebrew", detail: dependency("brew"), symbol: "mug.fill", ready: dependencyReady("brew"))
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Detect this Mac and propose sensible defaults", systemImage: "laptopcomputer.and.arrow.down")
                    Label("Choose reusable profiles instead of individual install commands", systemImage: "square.stack.3d.up")
                    Label("Build first, request administrator approval only for activation", systemImage: "lock.shield")
                    Label("Verify the active system before reporting success", systemImage: "checkmark.seal")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }

            Spacer()
            HStack {
                Spacer()
                Button("Configure This Mac", action: installer.continueFromWelcome)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!installer.setupStatus.isReady)
            }
        }
        .padding(36)
    }

    private var configuration: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Choose this Mac's configuration")
                    .font(.largeTitle.weight(.semibold))
                Text("The current Mac name is only a suggestion. Apply a saved machine from this checkout, or explicitly create a new one.")
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Saved machines")
                            .font(.title2.weight(.semibold))
                        Spacer()
                        Text("Detected: \(installer.detectedHostname)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }

                    if installer.availableMachines.isEmpty {
                        Label(
                            "No saved Darwin machine configurations were found in flake.nix.",
                            systemImage: "tray"
                        )
                        .foregroundStyle(.secondary)
                        .padding(14)
                    } else {
                        LazyVGrid(
                            columns: [GridItem(.flexible()), GridItem(.flexible())],
                            spacing: 12
                        ) {
                            ForEach(installer.availableMachines) { machine in
                                machineCard(machine)
                            }
                        }
                    }

                    createMachineCard
                }

                if let machine = installer.selectedExistingMachine {
                    GroupBox("Selected machine configuration") {
                        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 12) {
                            GridRow {
                                Text("Configuration").foregroundStyle(.secondary)
                                Text(machine.id).font(.body.monospaced())
                            }
                            GridRow {
                                Text("Computer name").foregroundStyle(.secondary)
                                Text(machine.machineName)
                            }
                            GridRow {
                                Text("Hardware").foregroundStyle(.secondary)
                                Text(machineTypeLabel(machine.machineType))
                            }
                            GridRow {
                                Text("User").foregroundStyle(.secondary)
                                Text(machine.username)
                            }
                            GridRow {
                                Text("Profiles").foregroundStyle(.secondary)
                                Text(profileSummary(for: machine.profiles))
                            }
                        }
                        .padding(8)
                    }

                    Label(
                        "Nix Me will apply this saved configuration unchanged. Activation will rename this Mac to \(machine.hostname).",
                        systemImage: "checkmark.seal.fill"
                    )
                    .foregroundStyle(.green)
                } else if installer.isCreatingNewMachine {
                    GroupBox("New machine") {
                        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 14) {
                            GridRow {
                                Text("Hostname").foregroundStyle(.secondary)
                                TextField("my-mac", text: $installer.hostname)
                            }
                            GridRow {
                                Text("Display name").foregroundStyle(.secondary)
                                TextField("My Mac", text: $installer.machineName)
                            }
                            GridRow {
                                Text("Username").foregroundStyle(.secondary)
                                TextField("username", text: $installer.username)
                            }
                            GridRow {
                                Text("Hardware").foregroundStyle(.secondary)
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
                        .textFieldStyle(.roundedBorder)
                        .padding(8)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Profiles")
                            .font(.title2.weight(.semibold))
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            ForEach(FirstInstallationStore.profiles) { profile in
                                profileCard(profile)
                            }
                        }
                    }

                    Toggle(isOn: $installer.appStateEnabled) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Manage supported application settings")
                                .fontWeight(.semibold)
                            Text("Applies reviewed, portable preferences. Credentials and private application data remain local.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                }

                if let validation = installer.validationMessage {
                    Label(validation, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }

                HStack {
                    Button("Back", action: installer.goBack)
                    Spacer()
                    Button("Review Configuration", action: installer.continueFromConfiguration)
                        .buttonStyle(.borderedProminent)
                        .disabled(installer.validationMessage != nil)
                }
            }
            .padding(36)
        }
    }

    private var review: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Review before building")
                .font(.largeTitle.weight(.semibold))
            Text(installer.configurationExists
                ? "Nix Me will apply the selected saved machine unchanged, even when this Mac currently has a different name."
                : "Nix Me will add this machine to the checkout, build the complete system, and then ask to activate it.")
                .foregroundStyle(.secondary)

            GroupBox {
                VStack(spacing: 0) {
                    reviewRow(
                        installer.configurationExists ? "Machine configuration" : "Hostname",
                        value: installer.hostname
                    )
                    if installer.configurationExists {
                        Divider()
                        reviewRow("Mac", value: installer.machineName)
                        Divider()
                        reviewRow("Hardware", value: machineTypeLabel)
                        Divider()
                        reviewRow("User", value: installer.username)
                        Divider()
                        reviewRow("Profiles", value: profileSummary)
                    } else {
                        Divider()
                        reviewRow("Mac", value: installer.machineName)
                        Divider()
                        reviewRow("Hardware", value: machineTypeLabel)
                        Divider()
                        reviewRow("User", value: installer.username)
                        Divider()
                        reviewRow("Profiles", value: profileSummary)
                        Divider()
                        reviewRow("Application settings", value: installer.appStateEnabled ? "Managed" : "Not managed")
                    }
                }
                .padding(8)
            }

            Label("The build runs as \(installer.username). macOS requests administrator approval only after the build is ready to activate.", systemImage: "lock.shield")
                .foregroundStyle(.secondary)

            Spacer()
            HStack {
                Button("Back", action: installer.goBack)
                Spacer()
                Button(installer.configurationExists ? "Apply Existing Configuration" : "Create and Apply") {
                    Task { await installer.install() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .padding(36)
    }

    private var progress: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(installer.errorMessage == nil ? "Setting up this Mac" : "Setup needs attention")
                .font(.largeTitle.weight(.semibold))
            Text(installer.errorMessage ?? installer.phaseMessage)
                .foregroundStyle(installer.errorMessage == nil ? Color.secondary : Color.orange)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 0) {
                ForEach(FirstInstallationPhase.allCases, id: \.rawValue) { phase in
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(phaseColor(phase).opacity(0.14))
                            if installer.isInstalling && installer.phase == phase {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: phase.rawValue < installer.phase.rawValue || installer.screen == .complete ? "checkmark" : phase.symbol)
                                    .foregroundStyle(phaseColor(phase))
                            }
                        }
                        .frame(width: 34, height: 34)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(phase.title).fontWeight(installer.phase == phase ? .semibold : .regular)
                            if installer.phase == phase {
                                Text(installer.phaseMessage)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                    .padding(.vertical, 11)
                    if phase != .verification { Divider().padding(.leading, 48) }
                }
            }
            .padding(14)
            .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 14))

            if let details = installer.errorDetails {
                DisclosureGroup("Technical details") {
                    ScrollView {
                        Text(details)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 8)
                    }
                    .frame(maxHeight: 150)
                }
            }

            Spacer()
            if installer.errorMessage != nil {
                HStack {
                    Button("Back to Review", action: installer.goBack)
                    Spacer()
                    Button("Retry") { Task { await installer.install() } }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(36)
    }

    private var complete: some View {
        VStack(spacing: 22) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 72))
                .foregroundStyle(.green)
            Text("This Mac is managed")
                .font(.largeTitle.weight(.semibold))
            Text("The configuration was built, activated, and verified. The managed Nix Me app is now available in your Applications folder.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 620)
            Button("Open Nix Me", action: openDashboard)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(36)
    }

    private func readinessCard(_ title: String, detail: String, symbol: String, ready: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: symbol).font(.title2).foregroundStyle(ready ? .green : .orange)
            Text(title).font(.headline)
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 14))
    }

    private func profileCard(_ profile: InstallationProfile) -> some View {
        let selected = installer.selectedProfiles.contains(profile.id)
        return Button {
            installer.toggleProfile(profile)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: profile.symbol)
                    .font(.title3)
                    .foregroundStyle(selected ? .white : .cyan)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 3) {
                    Text(profile.name).fontWeight(.semibold)
                    Text(profile.summary)
                        .font(.caption)
                        .foregroundStyle(selected ? .white.opacity(0.8) : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 78, alignment: .topLeading)
            .background(selected ? Color.accentColor : Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 13))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func machineCard(_ machine: InstallationMachineConfiguration) -> some View {
        let selected = installer.selectedExistingMachine?.id == machine.id
        let suggested = machine.id == installer.detectedHostname
        return Button {
            installer.selectExistingMachine(machine)
        } label: {
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .top) {
                    Image(systemName: selected ? "checkmark.circle.fill" : "desktopcomputer")
                        .font(.title3)
                        .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(machine.machineName)
                            .fontWeight(.semibold)
                        Text(machine.id)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if suggested {
                        Text("MATCH")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(.green.opacity(0.12), in: Capsule())
                    }
                }
                Text("\(machineTypeLabel(machine.machineType)) · \(profileSummary(for: machine.profiles))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
            .background(
                selected ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 13)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 13)
                    .stroke(selected ? Color.accentColor : Color.clear, lineWidth: 1.5)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var createMachineCard: some View {
        let selected = installer.isCreatingNewMachine
        return Button(action: installer.selectNewMachine) {
            HStack(spacing: 12) {
                Image(systemName: selected ? "checkmark.circle.fill" : "plus.circle")
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Create a new machine configuration")
                        .fontWeight(.semibold)
                    Text("Start from this Mac's detected name and hardware, then choose profiles.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                selected ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 13)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 13)
                    .stroke(selected ? Color.accentColor : Color.clear, lineWidth: 1.5)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func reviewRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 11)
    }

    private func dependencyReady(_ command: String) -> Bool {
        installer.setupStatus.dependencies.first(where: { $0.command == command })?.isAvailable == true
    }

    private func dependency(_ command: String) -> String {
        dependencyReady(command) ? "Ready" : "Not found"
    }

    private var profileSummary: String {
        profileSummary(for: Array(installer.selectedProfiles))
    }

    private func profileSummary(for ids: [String]) -> String {
        let namesByID = Dictionary(
            uniqueKeysWithValues: FirstInstallationStore.profiles.map { ($0.id, $0.name) }
        )
        let names = ids.sorted().map { namesByID[$0] ?? $0 }
        return names.isEmpty ? "Minimal base" : names.joined(separator: ", ")
    }

    private var machineTypeLabel: String {
        machineTypeLabel(installer.machineType)
    }

    private func machineTypeLabel(_ machineType: String) -> String {
        switch machineType {
        case "macbook-pro": "MacBook Pro"
        case "macmini": "Mac mini"
        case "vm": "Virtual machine"
        default: "MacBook"
        }
    }

    private func stepSymbol(_ screen: FirstInstallationScreen) -> String {
        if installer.screen.rawValue > screen.rawValue { return "checkmark.circle.fill" }
        if installer.screen == screen { return "circle.inset.filled" }
        return "circle"
    }

    private func stepColor(_ screen: FirstInstallationScreen) -> Color {
        installer.screen.rawValue >= screen.rawValue ? .accentColor : .secondary
    }

    private func phaseColor(_ phase: FirstInstallationPhase) -> Color {
        if installer.errorMessage != nil && installer.phase == phase { return .orange }
        if phase.rawValue <= installer.phase.rawValue { return .accentColor }
        return .secondary
    }
}
