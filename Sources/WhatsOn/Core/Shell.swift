import Foundation

/// Runs command-line tools (git, swift, bash) for the updater.
enum Shell {
    static let environment: [String: String] = {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin"
        env["GIT_TERMINAL_PROMPT"] = "0"   // never hang waiting for a password
        return env
    }()

    struct Failure: LocalizedError {
        let command: String
        let output: String
        var errorDescription: String? {
            let tail = output.split(separator: "\n").suffix(8).joined(separator: "\n")
            return "\(command) failed.\n\(tail)"
        }
    }

    @discardableResult
    static func run(_ executable: String, _ arguments: [String], in directory: URL? = nil,
                    onOutput: (@Sendable (String) -> Void)? = nil) async throws -> String {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.environment = environment
            if let directory { process.currentDirectoryURL = directory }

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            let buffer = OutputBuffer()

            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                let chunk = String(decoding: data, as: UTF8.self)
                buffer.append(chunk)
                onOutput?(chunk)
            }
            process.terminationHandler = { finished in
                pipe.fileHandleForReading.readabilityHandler = nil
                let rest = pipe.fileHandleForReading.readDataToEndOfFile()
                if !rest.isEmpty {
                    let chunk = String(decoding: rest, as: UTF8.self)
                    buffer.append(chunk)
                    onOutput?(chunk)
                }
                if finished.terminationStatus == 0 {
                    continuation.resume(returning: buffer.value)
                } else {
                    let name = ([URL(fileURLWithPath: executable).lastPathComponent] + arguments.prefix(2)).joined(separator: " ")
                    continuation.resume(throwing: Failure(command: name, output: buffer.value))
                }
            }
            do {
                try process.run()
            } catch {
                pipe.fileHandleForReading.readabilityHandler = nil
                continuation.resume(throwing: error)
            }
        }
    }
}

final class OutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var text = ""
    func append(_ s: String) { lock.lock(); text += s; lock.unlock() }
    var value: String { lock.lock(); defer { lock.unlock() }; return text }
}
