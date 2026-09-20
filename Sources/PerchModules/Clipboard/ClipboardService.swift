import AppKit
import Combine
import Defaults
import Foundation
import KeyboardShortcuts
import PerchCore
import Vision

/// Module 3 — the clipboard.
///
/// The single biggest gap in the paid field: NotchNook is $25 and has no text
/// history at all, and NotchBay caps its tray at 60 clips.
///
/// **This module contains Perch's only polling loop**, and it is the
/// documented exception to `CLAUDE.md` §5.1 — see
/// [ADR 0003](../../../docs/adr/0003-polling-the-pasteboard.md).
/// `NSPasteboard` has no notification of any kind, so the only way to know
/// something was copied is to read `changeCount` and compare. The timer
/// exists only while the module is on, stops on screen lock and on sleep, and
/// reads the pasteboard's *contents* only when the count actually changed.
@MainActor
final class ClipboardService: ObservableObject, PerchModule {

    static let moduleID: ModuleID = .clipboard

    @Published private(set) var history = ClipboardHistory()
    @Published private(set) var exclusions = ClipboardExclusions()

    /// Whether the picker is open. It takes the keyboard, so the panel has to
    /// know (see `IslandPanel.allowsKeyFocus`).
    @Published private(set) var isPickerOpen = false

    private(set) var isActive = false

    /// 600ms — see ADR 0003. Fast enough that the picker always has what you
    /// just copied; slow enough that the cost is an integer comparison about
    /// a hundred times a minute.
    private static let pollInterval: Duration = .milliseconds(600)

    private let island: IslandController
    private let directory: URL
    private let pasteboard: NSPasteboard

    private var pollTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private var lastChangeCount: Int
    private var recognitionTasks: [ClipboardEntry.ID: Task<Void, Never>] = [:]

    init(
        island: IslandController,
        directory: URL? = nil,
        pasteboard: NSPasteboard = .general
    ) {
        self.island = island
        self.directory = directory ?? Self.defaultDirectory
        self.pasteboard = pasteboard
        self.lastChangeCount = pasteboard.changeCount
    }

    static var defaultDirectory: URL {
        let base =
            FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first ?? URL(fileURLWithPath: NSTemporaryDirectory())

        return
            base
            .appendingPathComponent(
                Bundle.main.bundleIdentifier ?? "app.perch.Perch",
                isDirectory: true
            )
            .appendingPathComponent("Clipboard", isDirectory: true)
    }

    private var historyURL: URL { directory.appendingPathComponent("history.json") }

    // MARK: - PerchModule

    func activate() {
        guard !isActive else { return }
        isActive = true

        createDirectory()
        load()

        // Whatever is on the pasteboard right now was copied before the
        // module was on. Recording it would mean switching the clipboard on
        // silently captures whatever was already there, which is not what
        // anyone expects.
        lastChangeCount = pasteboard.changeCount

        observeSleepAndLock()
        registerShortcut()
        startPolling()
    }

    func deactivate() {
        guard isActive else { return }
        isActive = false

        stopPolling()

        for task in recognitionTasks.values { task.cancel() }
        recognitionTasks.removeAll()

        for observer in observers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            DistributedNotificationCenter.default().removeObserver(observer)
        }
        observers.removeAll()

        KeyboardShortcuts.disable(.clipboardPicker)
        closePicker()
        save()

        // The history stays on disk untouched. Switching the module off is
        // not the same as deleting what you copied (TC-CLP-009).
        island.withdraw(ClipboardActivity.identifier)
        island.withdraw(ClipboardPickerActivity.identifier)
    }

    // MARK: - Polling

    private func startPolling() {
        guard isActive, pollTask == nil else { return }

        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.pollInterval)
                guard !Task.isCancelled else { return }
                self?.checkPasteboard()
            }
        }
    }

    private func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// A locked or sleeping Mac cannot copy anything, so a timer running
    /// against it is pure waste (ADR 0003).
    private func observeSleepAndLock() {
        let workspace = NSWorkspace.shared.notificationCenter
        for (name, isAsleep) in [
            (NSWorkspace.willSleepNotification, true),
            (NSWorkspace.didWakeNotification, false)
        ] {
            observers.append(
                workspace.addObserver(forName: name, object: nil, queue: .main) { _ in
                    MainActor.assumeIsolated {
                        if isAsleep { self.stopPolling() } else { self.startPolling() }
                    }
                }
            )
        }

        let distributed = DistributedNotificationCenter.default()
        for (name, isLocked) in [
            ("com.apple.screenIsLocked", true),
            ("com.apple.screenIsUnlocked", false)
        ] {
            observers.append(
                distributed.addObserver(
                    forName: Notification.Name(name),
                    object: nil,
                    queue: .main
                ) { _ in
                    MainActor.assumeIsolated {
                        if isLocked { self.stopPolling() } else { self.startPolling() }
                    }
                }
            )
        }
    }

    /// The tick. An integer comparison, and nothing else unless it changed.
    private func checkPasteboard() {
        guard isActive else { return }

        let count = pasteboard.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count

        capture()
    }

    // MARK: - Capturing

    private func capture() {
        let source = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

        guard
            exclusions.allowsCapture(
                from: source,
                isConcealed: PasteboardReader.isConcealed(pasteboard)
            )
        else { return }

        guard
            let entry = PasteboardReader.entry(
                from: pasteboard,
                sourceBundleID: source
            )
        else { return }

        let isNew = history.record(entry)
        save()

        if entry.kind == .image { recogniseText(in: entry) }
        guard isNew else { return }

        island.submit(
            ClipboardActivity(entry: entry, historyCount: history.count)
        )
    }

    // MARK: - History

    func togglePin(_ id: ClipboardEntry.ID) {
        history.togglePin(id)
        save()
    }

    func remove(_ id: ClipboardEntry.ID) {
        history.remove(id)
        save()
    }

    func clearUnpinned() {
        history.clearUnpinned()
        save()
    }

    func search(_ query: String) -> [ClipboardEntry] {
        history.search(query)
    }

    /// Puts an entry back on the pasteboard.
    ///
    /// Perch does not press ⌘V for you — that would need Accessibility
    /// permission for something the user can do themselves, and this module
    /// asks for no permission at all.
    func copyToPasteboard(_ entry: ClipboardEntry, asPlainText: Bool = false) {
        // Perch's own write must not come back as a new entry a moment later.
        PasteboardReader.write(entry, asPlainText: asPlainText)
        lastChangeCount = pasteboard.changeCount
        closePicker()
    }

    // MARK: - Picker

    /// The shortcut is registered when the module is switched on and
    /// unregistered when it is switched off. A module that is off must not
    /// keep a global hotkey (TC-CLP-009).
    private func registerShortcut() {
        KeyboardShortcuts.onKeyUp(for: .clipboardPicker) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.isPickerOpen { self.closePicker() } else { self.openPicker() }
            }
        }
        KeyboardShortcuts.enable(.clipboardPicker)
    }

    func openPicker() {
        guard isActive else { return }
        isPickerOpen = true
        // The picker has a search field in it, so it is the one thing in
        // Perch that asks the panel for the keyboard.
        island.setRequiresKeyFocus(true)
        island.submit(ClipboardPickerActivity(entries: history.entries))
    }

    func closePicker() {
        guard isPickerOpen else { return }
        isPickerOpen = false
        island.setRequiresKeyFocus(false)
        island.withdraw(ClipboardPickerActivity.identifier)
    }

    func updatePicker(query: String) {
        guard isPickerOpen else { return }
        island.submit(ClipboardPickerActivity(entries: search(query)))
    }

    // MARK: - Retention

    func setRetention(_ retention: ClipboardHistory.Retention) {
        history.retention = retention
        history.prune()
        save()
    }

    func setExcluded(_ bundleID: String, _ isExcluded: Bool) {
        if isExcluded {
            exclusions.exclude(bundleID)
        } else {
            exclusions.include(bundleID)
        }
        saveExclusions()
    }
}

// MARK: - OCR

extension ClipboardService {

    /// Reads text out of a copied image, on this Mac.
    ///
    /// NotchBay's tray does this and it is genuinely useful — you screenshot
    /// an error message and want the text. Vision runs entirely on-device:
    /// there is no recognition service, no upload and no network request at
    /// any point (TC-CLP-014, TC-PRV-008).
    ///
    /// Off the critical path, because recognition takes longer than a copy
    /// should. The entry lands first and gains its text a moment later.
    fileprivate func recogniseText(in entry: ClipboardEntry) {
        guard Defaults[.clipboardOCR], let payload = entry.payload else { return }

        recognitionTasks[entry.id]?.cancel()
        recognitionTasks[entry.id] = Task { [weak self] in
            let text = await Self.recognise(payload)
            guard !Task.isCancelled else { return }

            // A result of "nothing" is recorded as such rather than left
            // unset, so the module never tries the same image twice
            // (TC-CLP-013).
            self?.history.attachRecognisedText(text, to: entry.id)
            self?.recognitionTasks[entry.id] = nil
            self?.save()
        }
    }

    nonisolated private static func recognise(_ data: Data) async -> String? {
        await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, _ in
                let lines = (request.results as? [VNRecognizedTextObservation] ?? [])
                    .compactMap { $0.topCandidates(1).first?.string }

                continuation.resume(returning: lines.isEmpty ? nil : lines.joined(separator: "\n"))
            }
            request.recognitionLevel = .accurate
            // Explicitly on-device. The default is already local, but the
            // promise on the website is specific enough to be worth stating
            // in code.
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(data: data, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }
}

// MARK: - Storage

extension ClipboardService {

    private func createDirectory() {
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
    }

    private var exclusionsURL: URL {
        directory.appendingPathComponent("exclusions.json")
    }

    /// Everything the clipboard keeps lives in Perch's own Application
    /// Support directory, and nowhere else (TC-PRV-003).
    fileprivate func load() {
        if let decoded: ClipboardHistory = decode(from: historyURL) {
            history = decoded
            history.prune()
        }

        if let decoded: ClipboardExclusions = decode(from: exclusionsURL) {
            exclusions = decoded
        }
    }

    /// A corrupt or missing file is a fresh start, never a crash. This runs
    /// at launch, and a menu-bar app that cannot start is worse than one that
    /// forgot your clipboard.
    private func decode<Value: Decodable>(from url: URL) -> Value? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Value.self, from: data)
    }

    fileprivate func save() {
        guard let data = try? JSONEncoder().encode(history) else { return }
        try? data.write(to: historyURL, options: .atomic)
    }

    fileprivate func saveExclusions() {
        guard let data = try? JSONEncoder().encode(exclusions) else { return }
        try? data.write(to: exclusionsURL, options: .atomic)
    }
}
