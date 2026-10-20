import Foundation

enum RuntimeEnvironment {
    static var process: [String: String] {
        process(merging: ProcessInfo.processInfo.environment)
    }

    static func process(merging base: [String: String]) -> [String: String] {
        var environment = base
        guard
            let runtimePath = Bundle.main.object(forInfoDictionaryKey: "NixMeRuntimePath") as? String,
            !runtimePath.isEmpty
        else {
            return environment
        }

        let existingPath = environment["PATH"].flatMap { $0.isEmpty ? nil : $0 }
        environment["PATH"] = [runtimePath, existingPath].compactMap { $0 }.joined(separator: ":")
        return environment
    }

    static var searchDirectories: [URL] {
        let path = process["PATH"] ?? ""
        return path.split(separator: ":").map {
            URL(fileURLWithPath: String($0), isDirectory: true)
        }
    }
}
