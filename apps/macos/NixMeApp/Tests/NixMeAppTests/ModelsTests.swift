import XCTest
@testable import NixMeApp

final class ModelsTests: XCTestCase {
    func testManagementBackendPrefersBundledExecutableAndFallsBackToCheckout() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let configuration = root.appendingPathComponent("configuration", isDirectory: true)
        let resources = root.appendingPathComponent("resources", isDirectory: true)
        let checkoutExecutable = configuration
            .appendingPathComponent("packages/management-api/bin/nix-me-api")
        let bundledExecutable = resources
            .appendingPathComponent("management-api/nix-me-api")
        let bundledEngine = resources
            .appendingPathComponent("management-api/nix-me-apps")
        defer { try? FileManager.default.removeItem(at: root) }

        try write("#!/bin/bash\n", to: checkoutExecutable)
        try write("#!/bin/bash\n", to: bundledExecutable)
        try write("#!/bin/bash\n", to: bundledEngine)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: checkoutExecutable.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bundledExecutable.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bundledEngine.path)

        XCTAssertEqual(
            ManagementBackend.bundledExecutable(
                named: "nix-me-apps",
                resourcesDirectory: resources
            )?.standardizedFileURL,
            bundledEngine.standardizedFileURL
        )

        XCTAssertEqual(
            ManagementBackend.executable(
                named: "nix-me-api",
                configurationDirectory: configuration,
                resourcesDirectory: resources
            ).standardizedFileURL,
            bundledExecutable.standardizedFileURL
        )

        try FileManager.default.removeItem(at: bundledExecutable)
        XCTAssertEqual(
            ManagementBackend.executable(
                named: "nix-me-api",
                configurationDirectory: configuration,
                resourcesDirectory: resources
            ).standardizedFileURL,
            checkoutExecutable.standardizedFileURL
        )
    }

    func testSnapshotDecodesAndCalculatesDashboardCounts() throws {
        let data = Data(fixture.utf8)
        let snapshot = try JSONDecoder().decode(ManagementSnapshot.self, from: data)

        XCTAssertEqual(snapshot.schemaVersion, 1)
        XCTAssertEqual(snapshot.host.hostname, "bellerofonte")
        XCTAssertEqual(snapshot.desiredSoftwareCount, 5)
        XCTAssertEqual(snapshot.installedHomebrewCount, 3)
        XCTAssertEqual(snapshot.projectAttentionCount, 1)
        XCTAssertEqual(snapshot.softwareUpdateCount, 3)
        XCTAssertEqual(snapshot.updates.macAppStore.first?.storeId, 497799835)
        XCTAssertEqual(snapshot.configuration.desiredSource?.revision, "def-dirty")
        XCTAssertEqual(snapshot.configuration.changes?.affectedAreaCount, 3)
        XCTAssertEqual(snapshot.configuration.changes?.files.first?.path, "nix/hosts/nabucodonosor.nix")
        XCTAssertEqual(snapshot.configuration.changes?.files.first?.statusLabel, "Modified")
        XCTAssertEqual(snapshot.softwareDifferences.count, 1)
        XCTAssertEqual(snapshot.softwareDifferences.first?.name, "git")
        XCTAssertEqual(snapshot.softwareDifferences.first?.change, .versionChanged)
        XCTAssertEqual(snapshot.softwareDifferences.first?.appliedVersion, "2.52.0")
        XCTAssertEqual(snapshot.softwareDifferences.first?.desiredVersion, "2.53.0")
        XCTAssertNil(snapshot.appState)
    }

    func testSnapshotDecodesOptionalAppStateStatus() throws {
        let data = try fixtureData(named: "snapshot-v1-app-state")
        let snapshot = try JSONDecoder().decode(ManagementSnapshot.self, from: data)
        let status = try XCTUnwrap(snapshot.appState)

        XCTAssertTrue(status.engine.available)
        XCTAssertEqual(status.engine.version, "0.1.0")
        XCTAssertEqual(status.configuredRecipeCount, 4)
        XCTAssertEqual(status.driftCount, 2)
        XCTAssertEqual(status.manualResidueCount, 1)
        XCTAssertEqual(status.differenceCount, 3)
        XCTAssertEqual(status.verification.verifiedRecipeCount, 1)
        XCTAssertEqual(status.verification.unverifiedRecipeCount, 3)
        XCTAssertEqual(status.lastApply.status, "succeeded")
        XCTAssertEqual(status.lastApply.time, "2026-10-05T17:56:00Z")
        XCTAssertEqual(status.lastApply.message, "Applied 4 configured recipes")
        XCTAssertEqual(status.warnings, ["One recipe needs review"])
        XCTAssertTrue(status.needsAttention)
        XCTAssertNil(snapshot.configuration.changes)
        let settings = try XCTUnwrap(snapshot.appStateSettings)
        XCTAssertEqual(settings.root, "config/app-state")
        XCTAssertTrue(settings.enabled)
        XCTAssertEqual(settings.activeProfiles, ["dev", "work"])
        XCTAssertEqual(settings.applications.map(\.id), ["rectangle", "ghostty", "installed-com-example-notes"])
        XCTAssertTrue(settings.applications[0].installed)
        XCTAssertFalse(settings.applications[1].installed)
        XCTAssertTrue(settings.applications[0].capturable)
        XCTAssertEqual(settings.applications[0].exportableSettings.count, 1)
        XCTAssertEqual(settings.applications[0].exportableSettings[0].kind, "preference")
        XCTAssertEqual(settings.applications[0].exportableSettings[0].requiresConfirmation, false)
        XCTAssertEqual(
            settings.applications[0].exportableSettings[0].source,
            "com.knollsoft.Rectangle/launchOnLogin"
        )
        XCTAssertFalse(settings.applications[1].capturable)
        XCTAssertEqual(settings.applications[1].managedPaths, ["~/.config/ghostty/config"])
        XCTAssertTrue(settings.applications[0].recipeAvailable)
        XCTAssertEqual(settings.applications[0].recipePath, "packages/app-state/recipes/rectangle.yaml")
        XCTAssertTrue(settings.applications[0].configured)
        XCTAssertEqual(settings.applications[0].configurationSources.map(\.scope), ["builtIn", "profile"])
        XCTAssertFalse(settings.applications[2].recipeAvailable)
        XCTAssertEqual(settings.applications[2].appPath, "/Applications/Notes Plus.app")
    }

    func testAppStateCountsKeepZeroDistinctFromUnavailable() {
        let engine = AppStateEngine(available: true, version: nil)
        let lastApply = AppStateLastApply(status: nil, time: nil, message: nil)
        let current = AppStateStatus(
            schemaVersion: 1,
            engine: engine,
            configuredRecipeCount: 0,
            driftCount: 0,
            manualResidueCount: 0,
            lastApply: lastApply,
            verification: AppStateVerification(verifiedRecipeCount: 0, unverifiedRecipeCount: 0),
            warnings: []
        )
        let unavailable = AppStateStatus(
            schemaVersion: 1,
            engine: engine,
            configuredRecipeCount: nil,
            driftCount: nil,
            manualResidueCount: nil,
            lastApply: lastApply,
            verification: AppStateVerification(verifiedRecipeCount: nil, unverifiedRecipeCount: nil),
            warnings: []
        )

        XCTAssertEqual(current.differenceCount, 0)
        XCTAssertFalse(current.hasUnavailableCounts)
        XCTAssertFalse(current.needsAttention)
        XCTAssertNil(unavailable.differenceCount)
        XCTAssertTrue(unavailable.hasUnavailableCounts)
        XCTAssertTrue(unavailable.needsAttention)
    }

    func testSettingsApplicationDefaultsNewCatalogFieldsForOlderSnapshots() throws {
        let data = Data(#"""
        {
          "id": "rectangle",
          "name": "Rectangle",
          "bundleId": "com.knollsoft.Rectangle",
          "installed": true,
          "capturable": true,
          "captureKinds": ["defaults"]
        }
        """#.utf8)

        let application = try JSONDecoder().decode(AppStateSettingsApplication.self, from: data)

        XCTAssertTrue(application.recipeAvailable)
        XCTAssertNil(application.recipePath)
        XCTAssertNil(application.appPath)
        XCTAssertFalse(application.configured)
        XCTAssertTrue(application.exportableSettings.isEmpty)
        XCTAssertTrue(application.managedPaths.isEmpty)
        XCTAssertTrue(application.manualSteps.isEmpty)
        XCTAssertNil(application.privateState)
        XCTAssertEqual(application.settingsCategory, .exportable)
        XCTAssertTrue(application.configurationSources.isEmpty)
    }

    func testPrivateStateReadinessDecodesWithoutSensitiveDetails() throws {
        for (rawReadiness, expectedReadiness, expectedLabel) in [
            ("ready", AppStatePrivateReadiness.ready, "Ready"),
            ("notReady", AppStatePrivateReadiness.notReady, "Not ready"),
            ("unknown", AppStatePrivateReadiness.unknown, "Unknown")
        ] {
            let data = Data(#"""
            {
              "id": "codex-cli",
              "name": "Codex CLI",
              "bundleId": "com.openai.codex.cli",
              "installed": true,
              "capturable": false,
              "captureKinds": [],
              "privateState": {
                "readiness": "\#(rawReadiness)",
                "exclusionReason": "Credentials and account data remain on this Mac."
              }
            }
            """#.utf8)

            let application = try JSONDecoder().decode(AppStateSettingsApplication.self, from: data)

            XCTAssertEqual(application.privateState?.readiness, expectedReadiness)
            XCTAssertEqual(application.privateReadinessLabel, expectedLabel)
            XCTAssertEqual(application.settingsCategory, .privateState)
            XCTAssertEqual(
                application.privateState?.exclusionReason,
                "Credentials and account data remain on this Mac."
            )
            XCTAssertTrue(application.manualSteps.isEmpty)
            XCTAssertTrue(application.exportableSettings.isEmpty)
        }

        let manualData = Data(#"""
        {
          "id": "manual-app",
          "name": "Manual App",
          "bundleId": "com.example.manual",
          "installed": true,
          "capturable": false,
          "captureKinds": [],
          "manualSteps": ["Complete setup manually"],
          "recipeAvailable": true
        }
        """#.utf8)
        let manualApplication = try JSONDecoder().decode(
            AppStateSettingsApplication.self,
            from: manualData
        )

        XCTAssertEqual(manualApplication.settingsCategory, .manual)
        XCTAssertNil(manualApplication.privateReadinessLabel)
    }

    func testHealthyLocalAIStatusFixture() throws {
        let snapshot = try decodeSnapshot(localAIStatusNamed: "local-ai-healthy-v1")
        let status = try XCTUnwrap(snapshot.localAI)

        XCTAssertEqual(status.schemaVersion, 1)
        XCTAssertEqual(status.health, .healthy)
        XCTAssertEqual(status.ds4Checkout.state, .ready)
        XCTAssertEqual(status.piDs4Checkout.state, .ready)
        XCTAssertEqual(status.extension.state, .linked)
        XCTAssertEqual(status.runtime.state, .built)
        XCTAssertEqual(status.model.state, .present)
        XCTAssertEqual(status.server.state, .stopped)
        XCTAssertEqual(status.configuration.state, .current)
        XCTAssertEqual(status.configuration.driftCount, 0)
        XCTAssertTrue(status.remediation.isEmpty)
        XCTAssertFalse(status.needsAttention)
    }

    func testDegradedLocalAIStatusFixture() throws {
        let status = try decodeLocalAIStatus(named: "local-ai-degraded-v1")

        XCTAssertEqual(status.health, .degraded)
        XCTAssertEqual(status.piDs4Checkout.state, .missing)
        XCTAssertEqual(status.runtime.state, .notBuilt)
        XCTAssertEqual(status.model.state, .missing)
        XCTAssertEqual(status.configuration.state, .drifted)
        XCTAssertEqual(status.configuration.driftCount, 2)
        XCTAssertEqual(status.remediation.count, 5)
        XCTAssertTrue(status.needsAttention)
    }

    func testUnavailableLocalAIStatusKeepsUnknownDistinctFromAbsent() throws {
        let status = try decodeLocalAIStatus(named: "local-ai-unavailable-v1")

        XCTAssertEqual(status.health, .unavailable)
        XCTAssertEqual(status.ds4Checkout.state, .unavailable)
        XCTAssertEqual(status.model.state, .unavailable)
        XCTAssertEqual(status.server.state, .unavailable)
        XCTAssertEqual(status.configuration.state, .unavailable)
        XCTAssertNil(status.configuration.driftCount)
        XCTAssertTrue(status.needsAttention)
    }

    func testMalformedOptionalLocalAIStatusDoesNotInvalidateSnapshot() throws {
        var snapshotObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(fixture.utf8)) as? [String: Any]
        )
        snapshotObject["localAI"] = try JSONSerialization.jsonObject(
            with: fixtureData(named: "local-ai-malformed")
        )
        let data = try JSONSerialization.data(withJSONObject: snapshotObject)
        let snapshot = try JSONDecoder().decode(ManagementSnapshot.self, from: data)

        XCTAssertNil(snapshot.localAI)
        XCTAssertEqual(snapshot.host.hostname, "bellerofonte")
    }

    func testLocalAIModelOperationDecodesProgressAndIntegrity() throws {
        let data = Data(#"""
        {
          "schemaVersion": 1,
          "operation": {
            "operationId": "model-123",
            "status": "running",
            "phase": "downloading",
            "pid": 123,
            "startedAt": "2026-10-05T20:00:00Z",
            "updatedAt": "2026-10-05T20:01:00Z",
            "finishedAt": null,
            "message": "Downloading DeepSeek V4 Flash Q2",
            "model": {"name":"DeepSeek V4 Flash Q2","path":"/tmp/ds4flash.gguf","downloadTarget":"ds4f-q2"},
            "progress": {"bytesDownloaded":1073741824,"expectedBytes":86973087744,"percent":1},
            "disk": {"requiredBytes":107374182400,"availableBytes":214748364800},
            "integrity": {"status":"pending","expectedSha256":null,"actualSha256":null},
            "stagePath": "/tmp/.nix-me-model-model-123",
            "processAlive": true
          }
        }
        """#.utf8)

        let response = try JSONDecoder().decode(LocalAIModelActionResponse.self, from: data)
        let operation = try XCTUnwrap(response.operation)
        XCTAssertTrue(operation.isRunning)
        XCTAssertEqual(operation.progress.percent, 1)
        XCTAssertEqual(operation.integrity.status, "pending")
        XCTAssertEqual(operation.processAlive, true)
    }

    func testActionClientPreservesStructuredFailureMessage() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try write(
            #"""
            #!/bin/bash
            printf '%s\n' '{"schemaVersion":1,"error":{"code":"missing_downloader","message":"Configured downloader is unavailable"}}'
            exit 69
            """#,
            to: root.appendingPathComponent("packages/management-api/bin/nix-me-action")
        )

        let client = ManagementActionClient(configurationDirectory: root)
        do {
            _ = try await client.startLocalAIModel()
            XCTFail("Expected the action to fail")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Configured downloader is unavailable"))
        }
    }

    func testApplyUsesActionWithUserBuildContract() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try write(
            #"""
            #!/bin/bash
            # NIX_ME_USER_BUILD_APPLY=1
            [[ "$1" == "apply" ]] || exit 64
            [[ "$NIX_ME_HOSTNAME" == "test-host" ]] || exit 65
            [[ "$NIX_ME_USERNAME" == "test-user" ]] || exit 66
            [[ "$NIX_ME_MACHINE_NAME" == "Test Mac" ]] || exit 67
            [[ "$NIX_ME_MACHINE_TYPE" == "test" ]] || exit 68
            [[ "$NIX_ME_SOURCE_REVISION" == "abc123" ]] || exit 69
            printf 'NIX_ME_PROGRESS\tbuilding\tBuilding test generation\n' >&2
            printf 'NIX_ME_PROGRESS\tactivating\tActivating test generation\n' >&2
            printf '%s\n' '{"schemaVersion":1,"success":true,"message":"Applied"}'
            """#,
            to: root.appendingPathComponent("packages/management-api/bin/nix-me-action")
        )

        let progress = ApplyProgressRecorder()
        let response = try await ManagementActionClient(configurationDirectory: root)
            .apply(
                hostname: "test-host",
                username: "test-user",
                machineName: "Test Mac",
                machineType: "test",
                sourceRevision: "abc123",
                onProgress: { progress.append($0) }
            )

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.message, "Applied")
        XCTAssertEqual(progress.values.map(\.phase), [.preparing, .building, .activating])
        XCTAssertEqual(progress.values.last?.message, "Activating test generation")
    }

    func testApplyDeliversProgressBeforeActionExits() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let acknowledgement = root.appendingPathComponent("progress-received")
        defer { try? FileManager.default.removeItem(at: root) }
        try write(
            #"""
            #!/bin/bash
            # NIX_ME_USER_BUILD_APPLY=1
            printf 'NIX_ME_PROGRESS\tbuilding\tBuilding test generation\n' >&2
            for _ in {1..100}; do
              [[ -f "\#(acknowledgement.path)" ]] && break
              sleep 0.01
            done
            [[ -f "\#(acknowledgement.path)" ]] || exit 70
            printf '%s\n' '{"schemaVersion":1,"success":true,"message":"Applied"}'
            """#,
            to: root.appendingPathComponent("packages/management-api/bin/nix-me-action")
        )

        let response = try await ManagementActionClient(configurationDirectory: root)
            .apply(
                hostname: "test-host",
                username: "test-user",
                onProgress: { progress in
                    guard progress.phase == .building else { return }
                    FileManager.default.createFile(
                        atPath: acknowledgement.path,
                        contents: Data()
                    )
                }
            )

        XCTAssertTrue(response.success)
        XCTAssertTrue(FileManager.default.fileExists(atPath: acknowledgement.path))
    }

    func testApplyFallsBackForActionWithoutUserBuildContract() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let action = root.appendingPathComponent("packages/management-api/bin/nix-me-action")
        let runner = root.appendingPathComponent("fake-osascript")
        let nix = root.appendingPathComponent("nix")
        let system = root.appendingPathComponent("built-system", isDirectory: true)
        let rebuild = system.appendingPathComponent("sw/bin/darwin-rebuild")
        try write("#!/bin/bash\nexit 1\n", to: action)
        try write(
            """
            #!/bin/bash
            [[ " $* " == *" build --json --no-link --impure "* ]] || exit 64
            [[ "$*" == *"path:\(root.path)#darwinConfigurations.test-host.system"* ]] || exit 65
            [[ "$HOSTNAME" == "test-host" ]] || exit 66
            [[ "$USERNAME" == "test-user" ]] || exit 67
            [[ "$MACHINE_NAME" == "Test Mac" ]] || exit 68
            [[ "$MACHINE_TYPE" == "test" ]] || exit 69
            [[ "$NIX_ME_SOURCE_REVISION" == "abc123" ]] || exit 70
            printf '%s\n' '[{"outputs":{"out":"\(system.path)"}}]'
            """,
            to: nix
        )
        try write(
            """
            #!/bin/bash
            [[ "$*" == *"nix-env -p /nix/var/nix/profiles/system --set"* ]] || exit 71
            [[ "$*" == *'set rebuildPath to systemPath & "/sw/bin/darwin-rebuild"'* ]] || exit 72
            [[ " $* " == *" -- \(system.path) test-user "* ]] || exit 73
            printf '%s\n' 'Compatibility apply succeeded'
            """,
            to: runner
        )
        try write("#!/bin/bash\n", to: rebuild)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: nix.path
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: runner.path
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: rebuild.path
        )

        let response = try await ManagementActionClient(
            configurationDirectory: root,
            administratorRunner: runner,
            nixOverride: nix
        ).apply(
            hostname: "test-host",
            username: "test-user",
            machineName: "Test Mac",
            machineType: "test",
            sourceRevision: "abc123"
        )

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.message, "Compatibility apply succeeded")
    }

    func testProjectPreviewEncodesRequestAndDecodesResponse() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try write(
            #"""
            #!/bin/bash
            payload="$(cat)"
            [[ "$1" == "project-preview" ]] || exit 64
            [[ "$NIX_ME_HOSTNAME" == "test-host" ]] || exit 65
            grep -Fq '"scope":"machine"' <<<"$payload" || exit 66
            grep -Fq '"branch":null' <<<"$payload" || exit 67
            cat <<'JSON'
            {
              "schemaVersion":1,
              "action":"project-preview",
              "success":true,
              "name":"example",
              "scope":"machine",
              "profile":null,
              "destination":"config/projects/machines/test-host.json",
              "changed":true,
              "written":false,
              "tracked":false,
              "replaced":false,
              "requiresSync":false,
              "project":{"url":"https://github.com/example/example.git","path":"src/example/example","branch":null,"remote":"origin","clone":true,"update":true},
              "preview":"{}",
              "message":"example will be added"
            }
            JSON
            """#,
            to: root.appendingPathComponent("packages/management-api/bin/nix-me-action")
        )

        let input = ProjectConfigurationInput(
            name: "example",
            url: "https://github.com/example/example.git",
            path: "src/example/example"
        )
        let response = try await ManagementActionClient(configurationDirectory: root)
            .previewProject(input, hostname: "test-host")

        XCTAssertEqual(response.destination, "config/projects/machines/test-host.json")
        XCTAssertEqual(response.project.path, "src/example/example")
        XCTAssertTrue(response.changed)
        XCTAssertFalse(response.written)
    }

    func testConfigurationGraphResolvesActiveProfilesAndImports() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try write(
            #"""
            {
              outputs = inputs: {
                darwinConfigurations.bellerofonte = mkDarwinSystem {
                  hostname = "bellerofonte";
                  machineType = "macbook-pro";
                  extraModules = [ ./nix/hosts/profiles/dev.nix ./nix/hosts/profiles/work.nix ];
                };
                darwinConfigurations.zion = mkDarwinSystem {
                  hostname = "zion";
                  extraModules = [ ./nix/hosts/profiles/maker.nix ];
                };
              };
            }
            """#,
            to: root.appendingPathComponent("flake.nix")
        )
        try write("{ imports = [ ../../../modules/darwin ]; }", to: root.appendingPathComponent("nix/hosts/types/shared/default.nix"))
        try write("{ imports = [ ../macbook/default.nix ]; }", to: root.appendingPathComponent("nix/hosts/types/macbook-pro/default.nix"))
        try write("{}", to: root.appendingPathComponent("nix/hosts/types/macbook/default.nix"))
        try write("{ imports = [ ../../types/macbook-pro ]; }", to: root.appendingPathComponent("nix/hosts/machines/bellerofonte/default.nix"))
        try write("# Development profile\n{}", to: root.appendingPathComponent("nix/hosts/profiles/dev.nix"))
        try write("{ projects.sets = [ (import ../../projects/work.nix) ]; }", to: root.appendingPathComponent("nix/hosts/profiles/work.nix"))
        try write("{}", to: root.appendingPathComponent("nix/hosts/profiles/maker.nix"))
        try write("{ imports = [ ./apps ./core.nix ]; }", to: root.appendingPathComponent("nix/modules/darwin/default.nix"))
        try write("{}", to: root.appendingPathComponent("nix/modules/darwin/apps/default.nix"))
        try write("{}", to: root.appendingPathComponent("nix/modules/darwin/core.nix"))
        try write("{}", to: root.appendingPathComponent("nix/modules/home-manager/default.nix"))
        try write("{}", to: root.appendingPathComponent("overlays/airjack.nix"))
        try write("{}", to: root.appendingPathComponent("nix/projects/work.nix"))

        let graph = try ConfigurationGraphScanner().scan(
            directory: root,
            hostname: "bellerofonte",
            machineType: "macbook-pro"
        )

        XCTAssertTrue(graph.node(at: "nix/hosts/profiles/dev.nix")?.isActive == true)
        XCTAssertTrue(graph.node(at: "nix/hosts/profiles/work.nix")?.isActive == true)
        XCTAssertFalse(graph.node(at: "nix/hosts/profiles/maker.nix")?.isActive == true)
        XCTAssertTrue(graph.node(at: "nix/modules/darwin/apps/default.nix")?.isActive == true)
        XCTAssertTrue(graph.node(at: "nix/projects/work.nix")?.isActive == true)
        XCTAssertEqual(graph.activeProfiles.map(\.displayName), ["dev", "work"])
        XCTAssertEqual(
            graph.importers(of: "nix/projects/work.nix").map(\.path),
            ["nix/hosts/profiles/work.nix"]
        )
        XCTAssertEqual(graph.node(at: "nix/hosts/profiles/dev.nix")?.summary, "Development profile")
    }

    func testConfigurationDirectoryRequiresFlake() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        XCTAssertFalse(ManagementAPIClient.isConfigurationDirectory(root))
        try write("{}", to: root.appendingPathComponent("flake.nix"))
        XCTAssertTrue(ManagementAPIClient.isConfigurationDirectory(root))
    }

    private func write(_ contents: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    private func fixtureData(named name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json"))
        return try Data(contentsOf: url)
    }

    private func decodeLocalAIStatus(named name: String) throws -> LocalAIStatus {
        try JSONDecoder().decode(LocalAIStatus.self, from: fixtureData(named: name))
    }

    private func decodeSnapshot(localAIStatusNamed name: String) throws -> ManagementSnapshot {
        var snapshotObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(fixture.utf8)) as? [String: Any]
        )
        snapshotObject["localAI"] = try JSONSerialization.jsonObject(with: fixtureData(named: name))
        let data = try JSONSerialization.data(withJSONObject: snapshotObject)
        return try JSONDecoder().decode(ManagementSnapshot.self, from: data)
    }

    private let fixture = #"""
    {
      "schemaVersion": 1,
      "generatedAt": "2026-08-12T10:00:00Z",
      "host": {"hostname":"bellerofonte","machineName":"Bellerofonte","machineType":"macbook-pro","username":"batman"},
      "configuration": {
        "path":"/Users/batman/.config/nixpkgs","exists":true,"appliedManifestPath":"/etc/nix-me/manifest.json",
        "applyState":"pending","generation":100,
        "desiredSource":{"revision":"def-dirty","dirty":true,"contentHash":"desired-source","lockHash":"desired-lock"},
        "appliedSource":{"revision":"abc","dirty":false,"contentHash":"applied-source","lockHash":"applied-lock"},
        "git":{"repository":true,"branch":"main","revision":"abc","dirty":false,"upstream":"origin/main","ahead":0,"behind":0,"remoteState":"upToDate"},
        "changes":{"softwareChanged":true,"projectsChanged":false,"appSettingsChanged":true,"flakeInputsChanged":false,"repositoryChanged":true,"filesComplete":true,"files":[{"status":"M","path":"nix/hosts/nabucodonosor.nix"}]}
      },
      "health": {"nix":{"available":true,"version":"nix 2.31"},"nixDarwin":{"available":true},"homebrew":{"available":true}},
      "inventory": {
        "desired":{"nixPackages":["git-2.53.0","jq-1.8.1"],"nixPackageDetails":[{"name":"git","fullName":"git-2.53.0","version":"2.53.0","description":"Version control","homepage":"https://git-scm.com","license":"GPL-2.0"},{"name":"jq","fullName":"jq-1.8.1","version":"1.8.1","description":"JSON processor","homepage":"https://jqlang.org","license":"MIT"}],"homebrew":{"formulae":["coreutils"],"casks":["raycast"],"masApps":{"Xcode":497799835}}},
        "applied":{"nixPackages":["git-2.52.0","jq-1.8.1"],"homebrew":{"formulae":["coreutils"],"casks":["raycast"],"masApps":{"Xcode":497799835}}},
        "installed":{"homebrew":{"formulae":[{"name":"coreutils","versions":["9.7"]}],"casks":[{"name":"raycast","versions":["1.0"]},{"name":"rectangle","versions":["1.0"]}]}}
      },
      "updates":{
        "homebrew":[{"name":"raycast","kind":"cask","installedVersions":["1.0"],"availableVersion":"1.1"}],
        "macAppStore":[{"name":"Xcode","kind":"mas","installedVersions":["26.3"],"availableVersion":"26.4","storeId":497799835}],
        "nixFlake":[{"name":"nixpkgs","kind":"nixFlake","installedVersions":["abc1234"],"availableVersion":"def5678"}]
      },
      "projects":[
        {"name":"platformatic","url":"https://github.com/platformatic/platformatic.git","path":"src/platformatic/platformatic","branch":null,"remote":"origin","clone":true,"update":true,"absolutePath":"/Users/batman/src/platformatic/platformatic","present":true,"isGitRepository":true,"status":"current","git":null},
        {"name":"desk","url":"https://github.com/platformatic/desk.git","path":"src/platformatic/desk","branch":null,"remote":"origin","clone":true,"update":true,"absolutePath":"/Users/batman/src/platformatic/desk","present":false,"isGitRepository":false,"status":"missing","git":null}
      ],
      "warnings":[]
    }
    """#
}

private final class ApplyProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [ApplyActionProgress] = []

    var values: [ApplyActionProgress] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ progress: ApplyActionProgress) {
        lock.lock()
        storage.append(progress)
        lock.unlock()
    }
}
