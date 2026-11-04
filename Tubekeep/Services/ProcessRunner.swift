import Foundation

enum ProcessRunner {
    struct Failure: LocalizedError {
        let status: Int32
        /// The last lines of stdout and stderr.
        let output: String

        var errorDescription: String? {
            let lines = output.split(whereSeparator: \.isNewline)
            let error = lines.last { $0.hasPrefix("ERROR") } ?? lines.last
            return error.map(String.init) ?? "Exited with status \(status)"
        }
    }

    /// Runs a tool from the bin folder, calling `onLine` for each line it prints (stdout and stderr).
    /// Returns stdout. Cancelling the task terminates the process.
    static func run(
        _ executable: URL,
        _ arguments: [String],
        qos: QualityOfService = .default,
        onLine: @escaping @Sendable (String) -> Void = { _ in }
    ) async throws -> String {
        try Task.checkCancellation()
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.qualityOfService = qos
        var environment = ProcessInfo.processInfo.environment
        // yt-dlp finds deno (for YouTube's JS challenges) and ffmpeg on PATH.
        environment["PATH"] = "\(Paths.bin.path):/usr/bin:/bin"
        process.environment = environment

        let stdout = LineReader(keepAll: true, onLine: onLine)
        let stderr = LineReader(keepAll: false, onLine: onLine)
        let outPipe = Pipe(), errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        let cancelled = Flag()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let group = DispatchGroup()
                for (pipe, reader) in [(outPipe, stdout), (errPipe, stderr)] {
                    group.enter()
                    pipe.fileHandleForReading.readabilityHandler = { handle in
                        let data = handle.availableData
                        if data.isEmpty {
                            handle.readabilityHandler = nil
                            reader.finish()
                            group.leave()
                        } else {
                            reader.feed(data)
                        }
                    }
                }
                group.enter()
                process.terminationHandler = { _ in group.leave() }
                group.notify(queue: .global()) {
                    if cancelled.isSet {
                        continuation.resume(throwing: CancellationError())
                    } else if process.terminationStatus == 0 {
                        continuation.resume(returning: stdout.text)
                    } else {
                        continuation.resume(throwing: Failure(
                            status: process.terminationStatus,
                            output: stdout.tail + "\n" + stderr.tail
                        ))
                    }
                }
                do {
                    try process.run()
                } catch {
                    for pipe in [outPipe, errPipe] {
                        pipe.fileHandleForReading.readabilityHandler = nil
                    }
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            cancelled.set()
            if process.isRunning { process.terminate() }
        }
    }
}

/// Splits a pipe's output into lines (on \n or \r, since progress output uses both).
private final class LineReader: @unchecked Sendable {
    private let lock = NSLock()
    private let keepAll: Bool
    private let onLine: @Sendable (String) -> Void
    private var buffer = Data()
    private var all = Data()
    private var recent: [String] = []

    init(keepAll: Bool, onLine: @escaping @Sendable (String) -> Void) {
        self.keepAll = keepAll
        self.onLine = onLine
    }

    func feed(_ data: Data) {
        lock.lock()
        if keepAll { all.append(data) }
        buffer.append(data)
        var lines: [String] = []
        while let index = buffer.firstIndex(where: { $0 == 0x0A || $0 == 0x0D }) {
            let line = String(decoding: buffer[buffer.startIndex..<index], as: UTF8.self)
            buffer.removeSubrange(buffer.startIndex...index)
            if !line.isEmpty { lines.append(line) }
        }
        remember(lines)
        lock.unlock()
        lines.forEach(onLine)
    }

    func finish() {
        lock.lock()
        let line = String(decoding: buffer, as: UTF8.self)
        buffer.removeAll()
        let lines = line.isEmpty ? [] : [line]
        remember(lines)
        lock.unlock()
        lines.forEach(onLine)
    }

    private func remember(_ lines: [String]) {
        recent.append(contentsOf: lines)
        if recent.count > 40 { recent.removeFirst(recent.count - 40) }
    }

    var text: String {
        lock.lock(); defer { lock.unlock() }
        return String(decoding: all, as: UTF8.self)
    }

    var tail: String {
        lock.lock(); defer { lock.unlock() }
        return recent.joined(separator: "\n")
    }
}

private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
    func set() { lock.lock(); value = true; lock.unlock() }
}

/// Limits how many jobs of one kind run at once.
actor Gate {
    private var available: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(_ limit: Int) { available = limit }

    func acquire() async {
        if available > 0 {
            available -= 1
        } else {
            await withCheckedContinuation { waiters.append($0) }
        }
    }

    func release() {
        if waiters.isEmpty {
            available += 1
        } else {
            waiters.removeFirst().resume()
        }
    }
}
