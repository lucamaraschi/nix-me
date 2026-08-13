import Foundation

struct UpdateActionResponse: Codable {
    let schemaVersion: Int
    let success: Bool
    let requiresApply: Bool
    let results: [UpdateActionResult]
}

struct UpdateActionResult: Codable {
    let name: String
    let kind: String
    let success: Bool
    let message: String
}

struct ApplyActionResponse: Codable {
    let schemaVersion: Int
    let success: Bool
    let message: String
}

private struct UpdateActionRequest: Codable {
    let items: [SoftwareUpdate]
}

struct ManagementActionClient {
    let configurationDirectory: URL

    func update(_ items: [SoftwareUpdate]) async throws -> UpdateActionResponse {
        let action = configurationDirectory.appendingPathComponent("bin/nix-me-action")
        let request = try JSONEncoder().encode(UpdateActionRequest(items: items))
        let data = try await run(action: action, command: "update", request: request)

        do {
            let response = try JSONDecoder().decode(UpdateActionResponse.self, from: data)
            guard response.schemaVersion == 1 else {
                throw ManagementAPIError.invalidResponse("Unsupported action schema version \(response.schemaVersion)")
            }
            return response
        } catch {
            if let apiError = error as? ManagementAPIError {
                throw apiError
            }
            throw ManagementAPIError.invalidResponse(error.localizedDescription)
        }
    }

    func apply(hostname: String, username: String) async throws -> ApplyActionResponse {
        let action = configurationDirectory.appendingPathComponent("bin/nix-me-action")
        let data = try await run(
            action: action,
            command: "apply",
            request: Data(),
            additionalEnvironment: [
                "NIX_ME_HOSTNAME": hostname,
                "NIX_ME_USERNAME": username
            ]
        )

        do {
            let response = try JSONDecoder().decode(ApplyActionResponse.self, from: data)
            guard response.schemaVersion == 1 else {
                throw ManagementAPIError.invalidResponse("Unsupported action schema version \(response.schemaVersion)")
            }
            return response
        } catch {
            if let apiError = error as? ManagementAPIError {
                throw apiError
            }
            throw ManagementAPIError.invalidResponse(error.localizedDescription)
        }
    }

    private func run(
        action: URL,
        command: String,
        request: Data,
        additionalEnvironment: [String: String] = [:]
    ) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let input = Pipe()
                let output = Pipe()
                let errors = Pipe()

                process.executableURL = URL(fileURLWithPath: "/bin/bash")
                process.arguments = [action.path, command]
                process.currentDirectoryURL = configurationDirectory
                process.standardInput = input
                process.standardOutput = output
                process.standardError = errors

                var environment = ProcessInfo.processInfo.environment
                environment["NIX_ME_CONFIG_DIR"] = configurationDirectory.path
                environment.merge(additionalEnvironment) { _, new in new }
                process.environment = environment

                do {
                    try process.run()
                    input.fileHandleForWriting.write(request)
                    try input.fileHandleForWriting.close()
                    let outputData = output.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    let errorData = errors.fileHandleForReading.readDataToEndOfFile()

                    guard process.terminationStatus == 0 else {
                        let message = String(data: errorData, encoding: .utf8)?
                            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown action error"
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
}
