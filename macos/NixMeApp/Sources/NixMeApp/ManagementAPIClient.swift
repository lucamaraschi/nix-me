import Foundation

enum ManagementAPIError: LocalizedError {
    case configurationNotFound
    case commandFailed(Int32, String)
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .configurationNotFound:
            return "Could not find the nix-me configuration. Set NIX_ME_CONFIG_DIR or clone it to ~/.config/nixpkgs."
        case let .commandFailed(code, message):
            return "nix-me API exited with code \(code): \(message)"
        case let .invalidResponse(message):
            return "The nix-me API returned invalid data: \(message)"
        }
    }
}

struct ManagementAPIClient {
    let configurationDirectory: URL

    init(configurationDirectory: URL? = nil) throws {
        if let configurationDirectory {
            self.configurationDirectory = configurationDirectory
            return
        }

        guard let discovered = Self.discoverConfigurationDirectory() else {
            throw ManagementAPIError.configurationNotFound
        }
        self.configurationDirectory = discovered
    }

    func snapshot() async throws -> ManagementSnapshot {
        let api = configurationDirectory.appendingPathComponent("bin/nix-me-api")
        let data = try await run(api: api, endpoint: "snapshot")

        do {
            let snapshot = try JSONDecoder().decode(ManagementSnapshot.self, from: data)
            guard snapshot.schemaVersion == 1 else {
                throw ManagementAPIError.invalidResponse("Unsupported schema version \(snapshot.schemaVersion)")
            }
            return snapshot
        } catch {
            if let apiError = error as? ManagementAPIError {
                throw apiError
            }
            throw ManagementAPIError.invalidResponse(error.localizedDescription)
        }
    }

    private func run(api: URL, endpoint: String) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let output = Pipe()
                let errors = Pipe()

                process.executableURL = URL(fileURLWithPath: "/bin/bash")
                process.arguments = [api.path, endpoint]
                process.currentDirectoryURL = configurationDirectory
                process.standardOutput = output
                process.standardError = errors

                var environment = ProcessInfo.processInfo.environment
                environment["NIX_ME_CONFIG_DIR"] = configurationDirectory.path
                process.environment = environment

                do {
                    try process.run()
                    // Drain stdout while the API runs so larger inventories cannot fill the pipe.
                    let outputData = output.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    let errorData = errors.fileHandleForReading.readDataToEndOfFile()

                    guard process.terminationStatus == 0 else {
                        let message = String(data: errorData, encoding: .utf8)?
                            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown error"
                        continuation.resume(throwing: ManagementAPIError.commandFailed(process.terminationStatus, message))
                        return
                    }
                    continuation.resume(returning: outputData)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func discoverConfigurationDirectory() -> URL? {
        let fileManager = FileManager.default
        let environment = ProcessInfo.processInfo.environment
        var candidates: [URL] = []

        if let configuredPath = environment["NIX_ME_CONFIG_DIR"], !configuredPath.isEmpty {
            candidates.append(URL(fileURLWithPath: configuredPath))
        }

        candidates.append(URL(fileURLWithPath: fileManager.currentDirectoryPath))
        candidates.append(fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".config/nixpkgs"))
        candidates.append(fileManager.homeDirectoryForCurrentUser.appendingPathComponent("src/lm/nix-me"))

        return candidates.first { candidate in
            fileManager.fileExists(atPath: candidate.appendingPathComponent("flake.nix").path)
                && fileManager.fileExists(atPath: candidate.appendingPathComponent("bin/nix-me-api").path)
        }?.resolvingSymlinksInPath()
    }
}
