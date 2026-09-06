import Foundation

enum ConfigurationBootstrapError: LocalizedError {
    case destinationExists(String)
    case cloneFailed(String)
    case invalidConfiguration(String)

    var errorDescription: String? {
        switch self {
        case let .destinationExists(path):
            "The destination already exists at \(path). Choose that folder or move it before cloning."
        case let .cloneFailed(message):
            "Could not clone the configuration: \(message)"
        case let .invalidConfiguration(path):
            "\(path) is not a nix-me configuration. It must contain flake.nix and bin/nix-me-api."
        }
    }
}

struct ConfigurationBootstrap {
    static let repositoryURL = "https://github.com/lucamaraschi/nix-me.git"

    static func clone(to destination: URL) async throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destination.path) {
            throw ConfigurationBootstrapError.destinationExists(destination.path)
        }
        try fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let errors = Pipe()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
                process.arguments = ["clone", repositoryURL, destination.path]
                process.standardError = errors

                do {
                    try process.run()
                    let errorData = errors.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    guard process.terminationStatus == 0 else {
                        let message = String(data: errorData, encoding: .utf8)?
                            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "Git exited with an error"
                        continuation.resume(throwing: ConfigurationBootstrapError.cloneFailed(message))
                        return
                    }
                    continuation.resume(returning: ())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
