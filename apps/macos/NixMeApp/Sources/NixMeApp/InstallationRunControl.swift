import Foundation

enum InstallationRunState: Equatable, Sendable {
    case idle
    case running
    case pauseRequested
    case paused
    case stopping
    case stopped

    var isPaused: Bool { self == .pauseRequested || self == .paused }
}

enum InstallationControlError: LocalizedError {
    case stopped

    var errorDescription: String? {
        "Installation stopped by the user. No further steps were started."
    }
}

final class InstallationRunControl: @unchecked Sendable {
    let controlFile: URL

    private let lock = NSLock()
    private var state: InstallationRunState = .idle
    private weak var process: Process?

    init(temporaryDirectory: URL = FileManager.default.temporaryDirectory) {
        controlFile = temporaryDirectory
            .appendingPathComponent("nix-me-install-\(UUID().uuidString).control")
    }

    deinit {
        try? FileManager.default.removeItem(at: controlFile)
    }

    var currentState: InstallationRunState {
        lock.withLock { state }
    }

    func start() throws {
        lock.withLock { state = .running }
        try write("running")
    }

    func requestPause() throws {
        lock.withLock {
            guard state == .running else { return }
            state = .pauseRequested
        }
        try write("pause")
    }

    func markPaused() {
        lock.withLock {
            if state == .pauseRequested { state = .paused }
        }
    }

    func resume() throws {
        lock.withLock {
            guard state.isPaused else { return }
            state = .running
        }
        try write("running")
    }

    func requestStop() {
        let activeProcess = lock.withLock { () -> Process? in
            guard state != .stopped else { return nil }
            state = .stopping
            return process
        }
        try? write("stop")
        activeProcess?.interrupt()
        if activeProcess?.isRunning == true {
            activeProcess?.terminate()
        }
    }

    func markStopped() {
        lock.withLock { state = .stopped }
        try? write("stop")
    }

    func register(_ process: Process) throws {
        let shouldStop = lock.withLock { () -> Bool in
            self.process = process
            return state == .stopping || state == .stopped
        }
        if shouldStop {
            process.terminate()
            throw InstallationControlError.stopped
        }
    }

    func unregister(_ process: Process) {
        lock.withLock {
            if self.process === process { self.process = nil }
        }
    }

    func waitIfPaused() async throws {
        while true {
            let snapshot = currentState
            if snapshot == .stopping || snapshot == .stopped {
                throw InstallationControlError.stopped
            }
            guard snapshot.isPaused else { return }
            markPaused()
            try await Task.sleep(for: .milliseconds(150))
        }
    }

    private func write(_ value: String) throws {
        try Data("\(value)\n".utf8).write(to: controlFile, options: .atomic)
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
