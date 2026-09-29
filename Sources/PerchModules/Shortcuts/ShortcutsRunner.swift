import Foundation
import PerchCore

/// Talks to the Shortcuts app.
///
/// Through `/usr/bin/shortcuts`, the command-line tool macOS has shipped
/// since Monterey — public, documented in its own `man` page, and the only
/// supported way for one app to list and run another user's Shortcuts. The
/// tool is a separate process, so a Shortcut that hangs hangs *it*, never
/// the island.
///
/// A protocol so the module's tests can run without the Shortcuts app and
/// without running anything real.
protocol ShortcutsRunning: Sendable {
    /// Every Shortcut in the library, by name. Empty when it cannot be read.
    func library() async -> [String]

    /// Runs one and waits for it.
    func run(_ name: String) async -> ShortcutOutcome

    /// Stops every run in progress. Called when the module switches off, so
    /// nothing the module started outlives it.
    func cancelAll()
}

final class ShortcutsCommandLine: ShortcutsRunning, @unchecked Sendable {

    private static let tool = URL(fileURLWithPath: "/usr/bin/shortcuts")

    /// Guarded by `lock`. Only ever touched for the length of an insert,
    /// a remove or a terminate.
    private var running: [ObjectIdentifier: Process] = [:]
    private let lock = NSLock()

    func library() async -> [String] {
        let result = await execute(["list"])
        guard result.status == 0 else { return [] }
        return result.output
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    func run(_ name: String) async -> ShortcutOutcome {
        // The name is one argument, never interpolated into a shell string:
        // a Shortcut called `x; rm -rf ~` is a Shortcut with an odd name.
        let result = await execute(["run", name])
        return ShortcutOutcome.from(
            exitCode: result.status,
            output: result.output,
            error: result.error
        )
    }

    func cancelAll() {
        lock.lock()
        let processes = Array(running.values)
        lock.unlock()

        for process in processes where process.isRunning {
            process.terminate()
        }
    }

    // MARK: - Internals

    private struct Result {
        let status: Int32
        let output: String
        let error: String
    }

    /// Runs the tool with a termination handler rather than
    /// `waitUntilExit`, so no thread sits blocked while a Shortcut takes
    /// its time.
    private func execute(_ arguments: [String]) async -> Result {
        guard FileManager.default.isExecutableFile(atPath: Self.tool.path) else {
            return Result(
                status: 127,
                output: "",
                error: String(localized: "The shortcuts tool is not on this Mac")
            )
        }

        let process = Process()
        process.executableURL = Self.tool
        process.arguments = arguments

        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error
        process.standardInput = FileHandle.nullDevice

        let key = ObjectIdentifier(process)

        return await withCheckedContinuation { continuation in
            process.terminationHandler = { [weak self] finished in
                // Read after exit: Shortcuts output is small, and reading
                // here rather than streaming keeps this one callback.
                let stdout = output.fileHandleForReading.readDataToEndOfFile()
                let stderr = error.fileHandleForReading.readDataToEndOfFile()
                self?.forget(key)

                continuation.resume(
                    returning: Result(
                        status: finished.terminationStatus,
                        output: String(bytes: stdout, encoding: .utf8) ?? "",
                        error: String(bytes: stderr, encoding: .utf8) ?? ""
                    )
                )
            }

            do {
                remember(process, as: key)
                try process.run()
            } catch {
                forget(key)
                process.terminationHandler = nil
                continuation.resume(
                    returning: Result(status: 126, output: "", error: error.localizedDescription)
                )
            }
        }
    }

    private func remember(_ process: Process, as key: ObjectIdentifier) {
        lock.lock()
        running[key] = process
        lock.unlock()
    }

    private func forget(_ key: ObjectIdentifier) {
        lock.lock()
        running[key] = nil
        lock.unlock()
    }
}
