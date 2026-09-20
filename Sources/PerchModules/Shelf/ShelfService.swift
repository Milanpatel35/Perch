import AppKit
import Defaults
import Foundation
import PerchCore
import UniformTypeIdentifiers

/// Module 2 — the Shelf.
///
/// Holds what you drag to the top of the screen until you want it somewhere
/// else. Everything it keeps lives in Perch's own Application Support
/// directory and nowhere else (TC-PRV-003), and the original file is copied,
/// never moved (TC-SHF-002).
@MainActor
final class ShelfService: ObservableObject, PerchModule, ShelfDropTarget {

    static let moduleID: ModuleID = .shelf

    @Published private(set) var store = ShelfStore()

    /// True while a drag is over the island. Drives the drop-target
    /// presentation, which outranks almost everything — the pointer is held
    /// down and the person needs to see where to let go.
    @Published private(set) var isDropTarget = false

    /// A conversion in flight, so the expanded island can show progress
    /// rather than appearing to hang (TC-SHF-014).
    @Published private(set) var conversion: ConversionProgress?

    /// The last refusal, shown in the island. A conversion that cannot be
    /// done says so; it does not quietly do nothing (TC-SHF-013).
    @Published private(set) var lastError: String?

    struct ConversionProgress: Equatable, Sendable {
        let itemName: String
        var fraction: Double
    }

    private(set) var isActive = false

    private let island: IslandController
    private let directory: URL
    private var conversionTask: Task<Void, Never>?

    init(island: IslandController, directory: URL? = nil) {
        self.island = island
        self.directory = directory ?? Self.defaultDirectory
    }

    /// `~/Library/Application Support/app.perch.Perch/Shelf`.
    ///
    /// Perch is not sandboxed — it reads pasteboard changes and drives the
    /// Accessibility API, neither of which is possible inside the sandbox —
    /// so "the container" is this directory, and everything the shelf and the
    /// clipboard keep stays inside it (TC-PRV-003).
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
            .appendingPathComponent("Shelf", isDirectory: true)
    }

    private var indexURL: URL {
        directory.appendingPathComponent("shelf.json")
    }

    // MARK: - PerchModule

    func activate() {
        guard !isActive else { return }
        isActive = true

        createDirectory()
        load()

        // Anything whose copy has gone since last launch greys out rather
        // than dangling (TC-SHF-005).
        store.refreshAvailability { FileManager.default.fileExists(atPath: $0) }

        present()
    }

    func deactivate() {
        guard isActive else { return }
        isActive = false

        conversionTask?.cancel()
        conversionTask = nil
        conversion = nil
        isDropTarget = false
        lastError = nil

        save()
        island.withdraw(ShelfActivity.identifier)
    }

    /// Called on quit. Honours the clear-on-quit switch, which is off by
    /// default — a shelf that empties itself without being asked has lost
    /// somebody's file (TC-SHF-008).
    func applicationWillQuit() {
        guard Defaults[.shelfClearOnQuit] else {
            save()
            return
        }
        clearAll()
    }

    // MARK: - Drop target

    func beginDrag() {
        guard isActive, Defaults[.dragToOpenShelf] else { return }
        isDropTarget = true
        present()
        island.send(.dragEntered)
    }

    func endDrag() {
        guard isDropTarget else { return }
        isDropTarget = false
        present()
    }

    // MARK: - Accepting

    /// Takes what was dropped.
    ///
    /// - Returns: how many items were accepted. Zero means the drop carried
    ///   nothing the shelf understands, which the island says rather than
    ///   swallowing.
    @discardableResult
    func accept(_ providers: [NSItemProvider]) async -> Int {
        var accepted: [ShelfItem] = []

        for provider in providers {
            if let item = await self.item(from: provider) {
                accepted.append(item)
            }
        }

        endDrag()
        guard !accepted.isEmpty else { return 0 }

        store.add(accepted)
        save()
        present()
        return accepted.count
    }

    /// Adds a file already on disk — the camera's snapshot button, or a
    /// finished conversion.
    @discardableResult
    func add(fileAt url: URL) -> ShelfItem? {
        guard let item = copyIntoShelf(url) else { return nil }
        store.add([item])
        save()
        present()
        return item
    }

    func remove(_ id: ShelfItem.ID) {
        guard let removed = store.remove(id) else { return }
        if let path = removed.storedPath {
            try? FileManager.default.removeItem(atPath: path)
        }
        save()
        present()
    }

    func clearAll() {
        for item in store.items {
            guard let path = item.storedPath else { continue }
            try? FileManager.default.removeItem(atPath: path)
        }
        store.removeAll()
        save()
        present()
    }

    // MARK: - Conversion

    func conversions(for item: ShelfItem) -> [ShelfConversion] {
        guard item.kind == .file else { return [] }
        return ShelfConversion.available(forFileNamed: item.name)
    }

    /// Converts a shelved file and puts the result on the shelf beside it.
    func convert(_ item: ShelfItem, using conversion: ShelfConversion) {
        guard let source = item.storedURL else { return }

        conversionTask?.cancel()
        self.conversion = ConversionProgress(itemName: item.name, fraction: 0)
        lastError = nil

        conversionTask = Task { [weak self, directory] in
            guard let self else { return }
            do {
                let output = try await FileConverter.convert(
                    source,
                    using: conversion,
                    into: directory,
                    progress: { [weak self] fraction in
                        self?.conversion?.fraction = fraction
                    }
                )
                guard !Task.isCancelled else { return }
                self.finishConversion(adding: output)
            } catch {
                guard !Task.isCancelled else { return }
                self.finishConversion(
                    failedWith: (error as? ShelfConversionError)?.message
                        ?? error.localizedDescription
                )
            }
        }
    }

    private func finishConversion(adding output: URL) {
        conversion = nil
        let attributes = try? FileManager.default.attributesOfItem(
            atPath: output.path
        )
        store.add([
            ShelfItem(
                kind: .file,
                name: output.lastPathComponent,
                storedPath: output.path,
                originalPath: output.path,
                byteCount: (attributes?[.size] as? NSNumber)?.int64Value ?? 0
            )
        ])
        save()
        present()
    }

    private func finishConversion(failedWith message: String) {
        conversion = nil
        lastError = message
        present()
    }

    // MARK: - Island

    private func present() {
        guard isActive else { return }

        guard !store.isEmpty || isDropTarget else {
            island.withdraw(ShelfActivity.identifier)
            return
        }

        island.submit(
            ShelfActivity(items: store.items, isDropTarget: isDropTarget)
        )
    }
}

// MARK: - Storage

extension ShelfService {

    private func createDirectory() {
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
    }

    /// Reads the index. A corrupt or missing file is an empty shelf, never a
    /// crash — this runs at launch, and a menu-bar app that cannot start is
    /// worse than one that forgot what was on the shelf.
    private func load() {
        guard let data = try? Data(contentsOf: indexURL),
            let decoded = try? JSONDecoder().decode(ShelfStore.self, from: data)
        else { return }
        store = decoded
    }

    /// Writes the index. Atomic, so a crash mid-write cannot leave a
    /// half-written file to fail the next launch (TC-SHF-004).
    private func save() {
        guard let data = try? JSONEncoder().encode(store) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }

    /// Copies a file into the shelf directory.
    ///
    /// A **copy**. The original is never moved, renamed or touched, which is
    /// the whole of TC-SHF-002 — a shelf that moved your file would be a
    /// filing system, and a surprising one.
    private func copyIntoShelf(_ url: URL) -> ShelfItem? {
        let manager = FileManager.default
        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return nil
        }

        let destination = FileConverter.uniqueURL(
            named: url.deletingPathExtension().lastPathComponent,
            extension: url.pathExtension,
            in: directory
        )

        do {
            try manager.copyItem(at: url, to: destination)
        } catch {
            return nil
        }

        return ShelfItem(
            // A folder is one item, not its contents (TC-SHF-006).
            kind: isDirectory.boolValue ? .folder : .file,
            name: url.lastPathComponent,
            storedPath: destination.path,
            originalPath: url.path,
            byteCount: size(of: destination)
        )
    }

    private func size(of url: URL) -> Int64 {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
    }

    /// Turns one dragged thing into a shelf item.
    ///
    /// Order matters: a drag from Finder carries both a file URL *and* a
    /// plain-text representation of its path, and taking the text first would
    /// turn every dropped file into a clipping.
    fileprivate func item(from provider: NSItemProvider) async -> ShelfItem? {
        if let url = await provider.loadFileURL() {
            return copyIntoShelf(url)
        }

        if let image = await provider.loadData(for: .image) {
            return ShelfItem(
                kind: .image,
                name: String(localized: "Image clipping"),
                payload: image,
                byteCount: Int64(image.count)
            )
        }

        // A dragged text selection becomes a clipping (TC-SHF-009).
        if let text = await provider.loadText(), !text.isEmpty {
            return ShelfItem(
                kind: .text,
                name: text.firstLine(limit: 60),
                payload: Data(text.utf8),
                byteCount: Int64(text.utf8.count)
            )
        }

        return nil
    }
}

// MARK: - NSItemProvider, made awaitable

/// `NSItemProvider` is not `Sendable`, and a drop arrives on the main actor,
/// so the whole parse stays there. The loader callbacks below fire on
/// whatever thread the provider chooses — which is fine, because all they do
/// is resume a continuation, and that is thread-safe by construction.
@MainActor
extension NSItemProvider {

    fileprivate func loadFileURL() async -> URL? {
        guard hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else {
            return nil
        }
        return await withCheckedContinuation { continuation in
            _ = loadObject(ofClass: URL.self) { url, _ in
                continuation.resume(returning: url?.isFileURL == true ? url : nil)
            }
        }
    }

    fileprivate func loadText() async -> String? {
        guard canLoadObject(ofClass: NSString.self) else { return nil }
        return await withCheckedContinuation { continuation in
            _ = loadObject(ofClass: NSString.self) { string, _ in
                continuation.resume(returning: (string as? NSString) as String?)
            }
        }
    }

    fileprivate func loadData(for type: UTType) async -> Data? {
        guard hasItemConformingToTypeIdentifier(type.identifier) else { return nil }
        return await withCheckedContinuation { continuation in
            loadDataRepresentation(forTypeIdentifier: type.identifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }
}

extension String {

    /// The first line, for naming a clipping. A clipping called by its whole
    /// contents is unreadable in a row 300 points wide.
    fileprivate func firstLine(limit: Int) -> String {
        let line =
            split(separator: "\n", omittingEmptySubsequences: true).first
            .map(Self.init) ?? self
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.count > limit
            ? String(trimmed.prefix(limit)) + "…"
            : trimmed
    }
}
