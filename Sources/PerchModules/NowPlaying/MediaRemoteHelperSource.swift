import AppKit
import Defaults
import Foundation
import PerchCore

extension Defaults.Keys {
    /// Every app, browsers included, through the helper (ADR 0010). On by
    /// default; off goes back to Music and Spotify only.
    static let nowPlayingAllApps = Key<Bool>("nowPlaying_allApps", default: true)
}

/// What is playing in *any* app — a Chrome or Safari tab, Prime Video,
/// YouTube, Podcasts — read through the helper Apple's own perl loads
/// (`Helpers/MediaRemote`, ADR 0010).
///
/// One helper process, started with the module and ended with it. It
/// prints a line per change and sleeps in between, so nothing here polls.
/// Its stdin is held open by this object: if Perch quits or crashes the pipe
/// closes and the helper exits on its own.
@MainActor
final class MediaRemoteHelperSource: NowPlayingSourcing {

    /// Where the helper lives. The app bundle's copy in a shipped build; a
    /// test passes its own.
    struct Helper {
        let perl: URL
        let script: URL
        let library: URL

        static var bundled: Self? {
            let perl = URL(fileURLWithPath: "/usr/bin/perl")
            guard
                let script = Bundle.main.url(forResource: "perch-mediaremote", withExtension: "pl"),
                let library = Bundle.main.privateFrameworksURL?
                    .appendingPathComponent("PerchMediaRemote.dylib"),
                FileManager.default.isExecutableFile(atPath: perl.path),
                FileManager.default.fileExists(atPath: library.path)
            else { return nil }
            return Self(perl: perl, script: script, library: library)
        }
    }

    /// Called once if the helper stops working — it exited without being
    /// asked, or MediaRemote refused it. The owner falls back.
    var onFailure: (@MainActor () -> Void)?

    private let helper: Helper?
    private var process: Process?
    private var input: Pipe?
    private var buffer = Data()
    private var latest: NowPlayingSnapshot?
    private var onChange: (@MainActor () -> Void)?
    private(set) var hasFailed = false

    init(helper: Helper? = .bundled) {
        self.helper = helper
    }

    var isAvailable: Bool { helper != nil && !hasFailed }

    func start(onChange: @escaping @MainActor () -> Void) {
        guard let helper, process == nil, !hasFailed else { return }
        self.onChange = onChange

        let process = Process()
        process.executableURL = helper.perl
        process.arguments = [helper.script.path, helper.library.path, "stream"]
        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task { @MainActor [weak self] in self?.received(data) }
        }
        process.terminationHandler = { [weak self] _ in
            Task { @MainActor [weak self] in self?.exited() }
        }

        do {
            try process.run()
        } catch {
            fail()
            return
        }
        self.process = process
        self.input = input
    }

    func stop() {
        guard let process else { return }
        self.process = nil
        onChange = nil
        (process.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
        process.terminationHandler = nil
        // Closing stdin is the helper's cue to exit; terminate is the backstop.
        try? input?.fileHandleForWriting.close()
        input = nil
        if process.isRunning { process.terminate() }
        buffer.removeAll()
        latest = nil
    }

    func readSnapshot() async -> NowPlayingSnapshot? {
        latest
    }

    func perform(_ command: NowPlayingCommand) {
        switch command {
        case .togglePlayPause: run("toggle")
        case .nextTrack: run("next")
        case .previousTrack: run("previous")
        }
    }

    func seek(to position: Duration) {
        let parts = position.components
        let seconds = Double(parts.seconds) + Double(parts.attoseconds) / 1e18
        run("seek", extra: ["PERCH_SEEK": String(seconds)])
    }

    // MARK: - Helper output

    private func received(_ data: Data) {
        guard process != nil, !data.isEmpty else { return }
        buffer.append(data)

        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            guard let read = MediaRemoteLine(Data(line)) else { continue }

            switch read {
            case .playing(var snapshot):
                snapshot.sourceName = snapshot.sourceBundleID.flatMap(Self.appName(for:))
                latest = snapshot
            case .nothing:
                latest = nil
            case .failed:
                fail()
                return
            }
            onChange?()
        }
    }

    private func exited() {
        // Exiting while still wanted is a failure; `stop()` clears `process`
        // first, so an asked-for exit never lands here as one.
        guard process != nil else { return }
        fail()
    }

    private func fail() {
        guard !hasFailed else { return }
        hasFailed = true
        let failure = onFailure
        stop()
        failure?()
    }

    /// A one-shot helper for a transport command. Short-lived, and nothing
    /// waits for it.
    private func run(_ command: String, extra: [String: String] = [:]) {
        guard let helper, !hasFailed else { return }
        let process = Process()
        process.executableURL = helper.perl
        process.arguments = [helper.script.path, helper.library.path, "command"]
        process.environment = ["PERCH_COMMAND": command].merging(extra) { $1 }
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }

    nonisolated private static func appName(for bundleID: String) -> String? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        else { return nil }
        return FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "")
    }
}

/// The helper, falling back to Music and Spotify (ADR 0008) if it cannot
/// run or stops working — so the island never goes blank because Apple
/// closed the door again.
@MainActor
final class AnyAppNowPlayingSource: NowPlayingSourcing {

    private let helper: MediaRemoteHelperSource
    private let fallback: any NowPlayingSourcing
    private let usesHelper: @MainActor () -> Bool
    private var active: (any NowPlayingSourcing)?
    private var onChange: (@MainActor () -> Void)?

    init(
        helper: MediaRemoteHelperSource = MediaRemoteHelperSource(),
        fallback: any NowPlayingSourcing = PlayerScriptingSource(),
        usesHelper: @escaping @MainActor () -> Bool = { Defaults[.nowPlayingAllApps] }
    ) {
        self.helper = helper
        self.fallback = fallback
        self.usesHelper = usesHelper
    }

    /// Whether the helper is the one reading. False after a fall back.
    var isUsingHelper: Bool { active === helper }

    var isAvailable: Bool { helper.isAvailable || fallback.isAvailable }

    func start(onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange

        guard usesHelper(), helper.isAvailable else {
            use(fallback)
            return
        }
        helper.onFailure = { [weak self] in
            guard let self, self.active === self.helper else { return }
            self.use(self.fallback)
            self.onChange?()
        }
        use(helper)
    }

    func stop() {
        active?.stop()
        active = nil
        helper.onFailure = nil
        onChange = nil
    }

    func readSnapshot() async -> NowPlayingSnapshot? {
        await active?.readSnapshot()
    }

    func perform(_ command: NowPlayingCommand) {
        active?.perform(command)
    }

    func seek(to position: Duration) {
        active?.seek(to: position)
    }

    private func use(_ source: any NowPlayingSourcing) {
        active = source
        if let onChange { source.start(onChange: onChange) }
    }
}
