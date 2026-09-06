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
    static let configurationDirectoryDefaultsKey = "NixMeConfigurationDirectory"
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
        let data = try await run(executable: api, arguments: ["snapshot"])

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

    func details(for item: SoftwareListItem) async throws -> PackageDetails {
        if let embeddedDetails = item.embeddedDetails {
            return embeddedDetails
        }

        let executable = configurationDirectory.appendingPathComponent("bin/nix-me-details")
        var arguments = [item.kind.rawValue, item.name]
        if let storeId = item.storeId {
            arguments.append(String(storeId))
        }
        let data = try await run(executable: executable, arguments: arguments)

        do {
            return try JSONDecoder().decode(PackageDetails.self, from: data)
        } catch {
            throw ManagementAPIError.invalidResponse(error.localizedDescription)
        }
    }

    func configurationGraph(hostname: String, machineType: String?) async throws -> ConfigurationGraph {
        let directory = configurationDirectory
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let graph = try ConfigurationGraphScanner().scan(
                        directory: directory,
                        hostname: hostname,
                        machineType: machineType
                    )
                    continuation.resume(returning: graph)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func run(executable: URL, arguments: [String]) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let output = Pipe()
                let errors = Pipe()

                process.executableURL = URL(fileURLWithPath: "/bin/bash")
                process.arguments = [executable.path] + arguments
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
                        let standardError = String(data: errorData, encoding: .utf8)?
                            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        let responseError = (try? JSONDecoder().decode(APIErrorResponse.self, from: outputData))?.error.message
                        let message = !standardError.isEmpty ? standardError : responseError ?? "Unknown error"
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

        if let savedPath = UserDefaults.standard.string(forKey: configurationDirectoryDefaultsKey),
           !savedPath.isEmpty {
            candidates.append(URL(fileURLWithPath: savedPath))
        }

        candidates.append(URL(fileURLWithPath: fileManager.currentDirectoryPath))
        candidates.append(fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".config/nixpkgs"))
        candidates.append(fileManager.homeDirectoryForCurrentUser.appendingPathComponent("src/lm/nix-me"))

        return candidates.first(where: isConfigurationDirectory)?.resolvingSymlinksInPath()
    }

    static func isConfigurationDirectory(_ directory: URL) -> Bool {
        let fileManager = FileManager.default
        return fileManager.fileExists(atPath: directory.appendingPathComponent("flake.nix").path)
            && fileManager.fileExists(atPath: directory.appendingPathComponent("bin/nix-me-api").path)
    }
}

private struct APIErrorResponse: Codable {
    struct ErrorBody: Codable {
        let message: String
    }

    let error: ErrorBody
}
