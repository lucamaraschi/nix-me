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

struct LocalAIModelActionResponse: Codable {
    let schemaVersion: Int
    let operation: LocalAIModelOperation?
}

struct LocalAIModelOperation: Codable, Equatable {
    let operationId: String
    let status: String
    let phase: String
    let message: String
    let startedAt: String
    let updatedAt: String
    let finishedAt: String?
    let processAlive: Bool?
    let model: LocalAIModelOperationModel
    let progress: LocalAIModelProgress
    let disk: LocalAIModelDisk
    let integrity: LocalAIModelIntegrity

    var isRunning: Bool { status == "running" }
}

struct LocalAIModelOperationModel: Codable, Equatable {
    let name: String
    let path: String
    let downloadTarget: String
}

struct LocalAIModelProgress: Codable, Equatable {
    let bytesDownloaded: Int64
    let expectedBytes: Int64
    let percent: Int
}

struct LocalAIModelDisk: Codable, Equatable {
    let requiredBytes: Int64
    let availableBytes: Int64
}

struct LocalAIModelIntegrity: Codable, Equatable {
    let status: String
    let expectedSha256: String?
    let actualSha256: String?
}

private struct UpdateActionRequest: Codable {
    let items: [SoftwareUpdate]
}

private struct LocalAIModelStartRequest: Codable {
    let expectedSha256: String?
}

struct ManagementActionClient {
    let configurationDirectory: URL

    func update(_ items: [SoftwareUpdate]) async throws -> UpdateActionResponse {
        let action = configurationDirectory.appendingPathComponent("packages/management-api/bin/nix-me-action")
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
        let action = configurationDirectory.appendingPathComponent("packages/management-api/bin/nix-me-action")
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

    func syncProjects(hostname: String) async throws -> ApplyActionResponse {
        let action = configurationDirectory.appendingPathComponent("packages/management-api/bin/nix-me-action")
        let data = try await run(
            action: action,
            command: "sync-projects",
            request: Data(),
            additionalEnvironment: ["NIX_ME_HOSTNAME": hostname]
        )

        do {
            return try JSONDecoder().decode(ApplyActionResponse.self, from: data)
        } catch {
            throw ManagementAPIError.invalidResponse(error.localizedDescription)
        }
    }

    func startLocalAIModel(expectedSha256: String? = nil) async throws -> LocalAIModelActionResponse {
        let request = try JSONEncoder().encode(LocalAIModelStartRequest(expectedSha256: expectedSha256))
        return try await runLocalAIModel(command: "local-ai-model-start", request: request)
    }

    func localAIModelStatus() async throws -> LocalAIModelActionResponse {
        try await runLocalAIModel(command: "local-ai-model-status", request: Data())
    }

    func cancelLocalAIModel() async throws -> LocalAIModelActionResponse {
        try await runLocalAIModel(command: "local-ai-model-cancel", request: Data())
    }

    private func runLocalAIModel(command: String, request: Data) async throws -> LocalAIModelActionResponse {
        let action = configurationDirectory.appendingPathComponent("packages/management-api/bin/nix-me-action")
        let data = try await run(action: action, command: command, request: request)
        do {
            let response = try JSONDecoder().decode(LocalAIModelActionResponse.self, from: data)
            guard response.schemaVersion == 1 else {
                throw ManagementAPIError.invalidResponse("Unsupported local-AI action schema version \(response.schemaVersion)")
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
                        let stderrMessage = String(data: errorData, encoding: .utf8)?
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        let structuredMessage = (try? JSONSerialization.jsonObject(with: outputData))
                            .flatMap { $0 as? [String: Any] }?["error"] as? [String: Any]
                        let message = structuredMessage?["message"] as? String
                            ?? (stderrMessage?.isEmpty == false ? stderrMessage : nil)
                            ?? "Unknown action error"
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
