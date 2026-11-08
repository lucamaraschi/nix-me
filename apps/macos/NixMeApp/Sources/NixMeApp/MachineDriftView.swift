import SwiftUI

struct MachineDriftOverviewCard: View {
    let plan: MachineDriftPlan?
    let isScanning: Bool
    let error: String?
    let review: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "desktopcomputer").font(.title).foregroundStyle(OxidePalette.amber)
            VStack(alignment: .leading, spacing: 5) {
                Text("MAC → CONFIGURATION").oxideLabel()
                Text(isScanning ? "Checking this Mac…" : plan?.summary ?? "Check this Mac against its configuration")
                    .font(.headline)
                Text(error ?? "Review local changes and choose what to save back to the repository.")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            Button("Review Mac Changes", action: review).buttonStyle(OxideButtonStyle(variant: .secondary))
        }.padding(20).background(OxidePalette.panel).overlay(Rectangle().stroke(OxidePalette.border))
    }
}

struct MachineDriftView: View {
    @ObservedObject var store: DashboardStore
    @State private var selected = Set<String>()
    @State private var proposal: MachineDriftProposal?
    @State private var reviewError: String?
    @State private var isPreparing = false
    @State private var confirmDiscard = false
    @State private var destinationChoices: [String: String] = [:]

    private var items: [MachineDriftItem] { store.machineDrift?.items ?? [] }
    private var selection: [MachineDriftItem] { items.filter { selected.contains($0.id) } }
    private var busy: Bool {
        store.isReconciling || store.isScanningDrift || store.isLoading || store.isApplying || store.isUpdating || isPreparing
    }
    private var destinations: [MachineDriftDestination] {
        guard let plan = store.machineDrift else { return [] }
        return plan.destinations ?? [MachineDriftDestination(id: "machine:\(plan.host)", scope: "machine", name: plan.host,
            source: "nix/hosts/machines/\(plan.host)/default.nix", path: plan.destination, hosts: [plan.host])]
    }
    private var assignments: [String: String] {
        MachineDriftSelection.destinationsByItem(selection, choices: destinationChoices, host: store.machineDrift?.host ?? "")
    }
    private func destination(for item: MachineDriftItem) -> MachineDriftDestination? {
        let id = MachineDriftSelection.destinationsByItem([item], choices: destinationChoices, host: store.machineDrift?.host ?? "")[item.id]
        return destinations.first { $0.id == id }
    }
    private var canPrepare: Bool {
        MachineDriftSelection.canPrepare(selection) && selection.allSatisfy { destination(for: $0)?.accepts([$0]) == true }
    }
    private var request: MachineDriftRequest? {
        guard let plan = store.machineDrift else { return nil }
        return MachineDriftRequest(token: plan.token, ids: selection.map(\.id), proposalToken: proposal?.proposalToken,
                                   destinationsByItem: assignments)
    }
    private var reviewed: Bool { request.map { proposal?.matches($0) == true } ?? false }

    var body: some View {
        ScrollViewReader { scroll in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Save this Mac's changes to configuration").font(.title2.bold())
                            Text("Choose what to keep and where each item belongs. Saving leaves this Mac as it is.").foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Scan Again", systemImage: "arrow.clockwise") { Task { await store.scanMachineDrift() } }
                            .buttonStyle(OxideButtonStyle(variant: .secondary)).disabled(busy)
                    }
                    if store.isReconciling || store.isScanningDrift || isPreparing {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text(store.machineDriftProgress ?? (isPreparing ? "Preparing the repository diff…" : "Comparing this Mac with the configuration…"))
                        }
                    }
                    if let error = store.machineDriftError { Text(error).foregroundStyle(OxidePalette.amber).textSelection(.enabled) }
                    if let result = store.machineDriftResult { resultView(result) }
                    if let publication = store.machineDrift?.publication {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(publication.title, systemImage: "arrow.up.doc").font(.headline)
                            Text(publication.detail).font(.callout).foregroundStyle(.secondary)
                            Text(publication.path).font(.caption.monospaced()).textSelection(.enabled)
                            Button("Show Saved Changes") { store.revealConfigurationFile(publication.path) }
                        }.padding(16).background(OxidePalette.panel)
                    }
                    if let plan = store.machineDrift {
                        if plan.needsSavingSupport == true {
                            Label("This checkout needs saving support. The review includes those setup files; nothing is changed yet.", systemImage: "info.circle")
                                .font(.callout).foregroundStyle(.secondary)
                        } else if plan.canKeepChanges == false {
                            Label("This checkout cannot safely accept these changes yet. Choose an updated checkout; no files have been written.", systemImage: "exclamationmark.triangle")
                                .font(.callout).foregroundStyle(OxidePalette.amber)
                        }
                        if !items.isEmpty {
                            HStack {
                                Text("\(selected.count) selected").font(.headline)
                                Button("Select All") { selected = Set(items.prefix(100).map(\.id)) }
                                Button("Clear") { selected = [] }
                                Spacer()
                            }.disabled(busy)
                            ForEach(["cask", "formula", "file"], id: \.self) { kind in
                                let group = items.filter { $0.kind == kind }
                                if let first = group.first {
                                    VStack(alignment: .leading, spacing: 0) {
                                        Text(first.category.uppercased()).oxideLabel(color: OxidePalette.green).padding(16)
                                        ForEach(group) { item in Divider(); driftRow(item) }
                                    }.background(OxidePalette.panel).overlay(Rectangle().stroke(OxidePalette.border))
                                }
                            }
                        } else {
                            Label(plan.summary, systemImage: plan.warnings.isEmpty ? "checkmark.circle" : "exclamationmark.triangle")
                                .font(.headline).padding(.vertical, 24)
                        }
                        if !plan.warnings.isEmpty {
                            DisclosureGroup("Scan notes (\(plan.warnings.count))") {
                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(Array(plan.warnings.enumerated()), id: \.offset) { _, warning in
                                        Text(warning).font(.callout).foregroundStyle(OxidePalette.amber)
                                    }
                                }.padding(.top, 10)
                            }
                        }
                        Text("Last scan: \(plan.checkedAt)").font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 16) {
                        if let reviewError { Text(reviewError).foregroundStyle(OxidePalette.amber).textSelection(.enabled) }
                        if let proposal, reviewed {
                            Text("Review the configuration changes").font(.title3.bold())
                            Text("Each item goes to its chosen destination. Effects happen on each host's next apply, not now.")
                                .font(.callout).foregroundStyle(.secondary)
                            ForEach(proposal.destinations ?? []) { destination in
                                VStack(alignment: .leading, spacing: 4) {
                                    Label(destination.title, systemImage: destination.symbol).font(.headline)
                                    ForEach(selection.filter { proposal.destinationsByItem?[$0.id] == destination.id }) { item in
                                        Text(item.saveEffect).font(.callout)
                                    }
                                    Text(destination.path).font(.caption.monospaced()).textSelection(.enabled)
                                }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(OxidePalette.panel)
                            }
                            if let impact = proposal.impact, !impact.isEmpty {
                                DisclosureGroup("Effects on \(impact.count) hosts") {
                                    VStack(alignment: .leading, spacing: 12) {
                                        ForEach(impact) { entry in
                                            VStack(alignment: .leading, spacing: 4) {
                                                Label(entry.host, systemImage: "desktopcomputer").font(.headline)
                                                ForEach(entry.effects, id: \.self) { Text($0).font(.callout).foregroundStyle(.secondary) }
                                            }
                                        }
                                    }.padding(.top, 8)
                                }
                            }
                            ForEach(proposal.localFiles) { file in
                                if let difference = file.difference {
                                    Text(file.id.replacingOccurrences(of: "file:", with: "")).font(.headline)
                                    diffView(difference)
                                }
                            }
                            if proposal.needsSavingSupport {
                                Text("Also adds the saving-support module and imports it in this checkout. Nix will validate all changes before accepting the save.")
                                    .font(.callout).foregroundStyle(OxidePalette.amber)
                            }
                            ForEach(proposal.files) { file in
                                if (proposal.destinations?.map(\.path) ?? [proposal.destination]).contains(file.path) {
                                    Text(file.path).font(.caption.monospaced()).textSelection(.enabled)
                                    diffView(file.difference)
                                } else {
                                    DisclosureGroup(file.path) { diffView(file.difference) }
                                }
                            }
                            Text("Review for private data. Saved file contents are plain text in the repository and Nix store.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }.id("configuration-review")
                    DisclosureGroup("What is checked?") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Homebrew selections and single managed dotfiles. Dependencies are excluded. Homebrew versions are not pinned; App Store apps, unmanaged files, and system preferences are not reconciled here.")
                                .font(.callout).foregroundStyle(.secondary)
                            Button("Review App Preferences") { store.selectedSection = .harness }
                        }.padding(.top, 8)
                    }
                }.padding(24)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !selection.isEmpty {
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(selection.count) SELECTED · \(Set(assignments.values).count) DESTINATION\(Set(assignments.values).count == 1 ? "" : "S")").oxideLabel(color: OxidePalette.green)
                            Text(selection.contains(where: { $0.kind == "file" }) && !reviewed
                                ? "Review reads the selected files. Nothing is saved yet."
                                : "Save locally, then commit and push with your Git client.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Menu("Other Action") {
                            Button("Discard Selected Mac Changes…", role: .destructive) { confirmDiscard = true }
                                .disabled(!selection.allSatisfy(\.canRestore))
                        }.fixedSize().disabled(busy)
                        Button(reviewed ? "Save to Configuration" : "Review Save") {
                            if reviewed { perform("keep") }
                            else { prepare { withAnimation { scroll.scrollTo("configuration-review", anchor: .top) } } }
                        }.buttonStyle(OxideButtonStyle(variant: .primary)).disabled(busy || !canPrepare)
                    }.padding(20).background(OxidePalette.panelRaised)
                        .overlay(alignment: .top) { Rectangle().fill(OxidePalette.border).frame(height: 1) }
                }
            }
        }
        .onChange(of: store.machineDrift?.token) { _, _ in selected = []; proposal = nil; reviewError = nil; destinationChoices = [:] }
        .onChange(of: selected) { _, _ in proposal = nil; reviewError = nil }
        .onChange(of: destinationChoices) { _, _ in proposal = nil; reviewError = nil }
        .confirmationDialog("Discard these Mac changes?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard Selected Changes", role: .destructive) { perform("restore") }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("CONFIGURATION → MAC\n\n" + selection.map(\.restoreEffect).joined(separator: "\n")
                + "\n\nThis changes your Mac, not the repository. Files are backed up; apps may be uninstalled without deleting their user data. Unselected items stay unchanged.")
        }
    }

    private func resultView(_ result: MachineDriftResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(result.message).font(.headline)
            ForEach(result.results) { item in
                Label("\(item.id): \(item.message)", systemImage: item.success ? "checkmark.circle" : "exclamationmark.triangle")
                    .foregroundStyle(item.success ? OxidePalette.green : OxidePalette.amber).textSelection(.enabled)
            }
            if result.success && result.action == "keep" {
                ForEach(result.filesWritten ?? [], id: \.self) { path in
                    Button("Show \(path)") { store.revealConfigurationFile(path) }
                }
                Button("Open Repository Folder") { store.openConfiguration() }
            }
        }.padding(16).background(OxidePalette.panel)
    }

    private func driftRow(_ item: MachineDriftItem) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Toggle(item.name, isOn: Binding(get: { selected.contains(item.id) }, set: { value in
                if value { selected.insert(item.id) } else { selected.remove(item.id) }
            })).labelsHidden().toggleStyle(.checkbox)
                .disabled(busy || (!selected.contains(item.id) && selected.count >= 100))
            Image(systemName: item.symbol).foregroundStyle(OxidePalette.green).frame(width: 24)
            VStack(alignment: .leading, spacing: 6) {
                Text(item.name).font(.headline)
                Text("Mac: \(item.current) · Configuration: \(item.expected)").font(.callout).foregroundStyle(.secondary)
                Text(item.saveEffect).font(.caption).foregroundStyle(OxidePalette.green)
                if item.conflict == true { Text("Both copies changed. Review before saving.").foregroundStyle(OxidePalette.amber) }
                if !item.canKeep && item.kind == "file" { Text("This redirected file cannot be saved automatically.").font(.caption).foregroundStyle(OxidePalette.amber) }
            }
            Spacer()
            if let destination = destination(for: item), item.canKeep {
                VStack(alignment: .leading, spacing: 6) {
                    Picker("Save to", selection: Binding(get: { destination.id }, set: { destinationChoices[item.id] = $0 })) {
                        ForEach(destinations.filter { $0.accepts([item]) }) { option in
                            Text(option.title).tag(option.id)
                        }
                    }.pickerStyle(.menu).accessibilityLabel("Destination for \(item.name)")
                        .disabled(busy || item.kind == "file")
                    Text(item.kind == "file" ? "Dotfiles stay on this machine" : "Applies to \(destination.hosts.count) host\(destination.hosts.count == 1 ? "" : "s")")
                        .font(.caption).foregroundStyle(.secondary)
                    DisclosureGroup("Destination details") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Hosts: \(destination.hosts.joined(separator: ", "))")
                            Text("Source: \(destination.source)").font(.caption.monospaced())
                            Text("Save file: \(destination.path)").font(.caption.monospaced())
                            if destination.scope != "machine" {
                                Text("Future hosts using this layer inherit it too. More specific exceptions are checked in the review.")
                            }
                        }.font(.caption).textSelection(.enabled).padding(.top, 6)
                    }
                }.frame(width: 320, alignment: .leading)
            }
        }.padding(16).accessibilityElement(children: .contain)
    }

    private func diffView(_ text: String) -> some View {
        GeometryReader { geometry in
            ScrollView([.horizontal, .vertical]) {
                Text(highlightedDiff(text)).font(.caption.monospaced()).textSelection(.enabled)
                    .fixedSize(horizontal: true, vertical: true)
                    .frame(minWidth: geometry.size.width, minHeight: geometry.size.height, alignment: .topLeading)
            }
        }.frame(height: 220).padding(12).background(OxidePalette.panel)
    }

    private func highlightedDiff(_ text: String) -> AttributedString {
        var result = AttributedString()
        for line in text.components(separatedBy: "\n") {
            var content = AttributedString(line + "\n")
            if line.hasPrefix("+") { content.foregroundColor = OxidePalette.green }
            else if line.hasPrefix("-") { content.foregroundColor = OxidePalette.amber }
            result.append(content)
        }
        return result
    }

    private func prepare(showReview: @escaping () -> Void) {
        guard let request else { return }
        isPreparing = true
        reviewError = nil
        Task {
            defer { isPreparing = false }
            do {
                let response = try await store.prepareMachineChanges(request)
                if store.machineDrift?.token == request.token && selected == Set(request.ids)
                    && assignments == request.destinationsByItem {
                    guard response.matches(request) else {
                        reviewError = "The management backend did not confirm each destination. Update the configuration checkout and try again. Nothing was saved."
                        showReview()
                        return
                    }
                    proposal = response
                    showReview()
                }
            } catch { reviewError = error.localizedDescription; showReview() }
        }
    }

    private func perform(_ command: String) {
        guard let request else { return }
        Task { await store.reconcileMachine(command, request: request) }
    }
}
