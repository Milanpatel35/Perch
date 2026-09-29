import Combine
import Defaults
import Foundation
import PerchCore

/// Module 13 — Shortcuts and automation.
///
/// Both directions (`docs/FEATURES.md` §13): favourite Shortcuts as buttons
/// on the island, and three ways for everything else to reach the island —
/// actions in the Shortcuts app, `perch://` URLs, and the `perch` CLI. The
/// last two are the same thing: the CLI builds a URL and opens it, and the
/// Shortcuts actions do too. So there is one front door, `handle(_:)`, and
/// it is the only code that decides what outside input is allowed to do.
///
/// **Nothing runs while nothing is asked.** Switching the module on starts
/// no process and reads no library; the library is read when the settings
/// pane asks for it, and a Shortcut runs when a person presses its button.
@MainActor
final class ShortcutsService: ObservableObject, PerchModule {

    static let moduleID: ModuleID = .shortcuts

    @Published private(set) var favourites: ShortcutFavourites
    @Published private(set) var library: [String] = []
    @Published private(set) var isReadingLibrary = false
    @Published private(set) var runningName: String?

    /// The last outside request turned away, and why. Shown in the pane so
    /// a script author can see what they got wrong without a console.
    @Published private(set) var lastRejection: PerchURL.Rejection?

    private(set) var isActive = false

    private let island: IslandController
    private let runner: any ShortcutsRunning

    /// Wired by the registry to the other modules. `false` means that
    /// module is off, and the island says so rather than doing nothing.
    var onAddToShelf: ((URL) -> Bool)?
    var onStartFocus: (() -> Bool)?

    private var runTask: Task<Void, Never>?
    private var libraryTask: Task<Void, Never>?

    init(island: IslandController, runner: any ShortcutsRunning = ShortcutsCommandLine()) {
        self.island = island
        self.runner = runner
        self.favourites = Defaults[.shortcutFavourites]
    }

    // MARK: - PerchModule

    func activate() {
        guard !isActive else { return }
        isActive = true
    }

    func deactivate() {
        guard isActive else { return }
        isActive = false

        runTask?.cancel()
        runTask = nil
        libraryTask?.cancel()
        libraryTask = nil
        runner.cancelAll()

        runningName = nil
        isReadingLibrary = false
        library = []
        lastRejection = nil
        island.withdrawAll(from: .shortcuts)
    }

    // MARK: - The front door

    /// Every `perch://` URL arrives here, whichever of the three ways in it
    /// took. Returns whether it was acted on.
    @discardableResult
    func handle(_ url: URL) -> Bool {
        guard isActive else { return false }

        switch PerchURL.parse(url) {
        case .success(let command):
            lastRejection = nil
            perform(command)
            return true
        case .failure(let rejection):
            lastRejection = rejection
            return false
        }
    }

    private func perform(_ command: PerchCommand) {
        switch command {
        case .notify(let message):
            island.submit(ShortcutsActivity.message(message))

        case .addToShelf(let file):
            if onAddToShelf?(file) != true {
                say(String(localized: "Couldn’t add to the shelf"), because: shelfReason(for: file))
            }

        case .startFocus:
            if onStartFocus?() != true {
                say(
                    String(localized: "Couldn’t start a focus session"),
                    because: String(localized: "The Focus module is switched off")
                )
            }
        }
    }

    private func shelfReason(for file: URL) -> String {
        FileManager.default.fileExists(atPath: file.path)
            ? String(localized: "The Shelf module is switched off")
            : String(localized: "No file at \(file.lastPathComponent)")
    }

    private func say(_ title: String, because body: String) {
        island.submit(ShortcutsActivity.message(.init(title: title, body: body, urgency: .normal)))
    }

    // MARK: - Running favourites

    /// Runs a favourite. One at a time: a second press while one is running
    /// is ignored rather than queued, because a queue of Shortcuts somebody
    /// pressed impatiently is not something anybody wants to watch execute.
    func run(_ name: String) {
        guard isActive, runningName == nil else { return }

        runningName = name
        island.submit(ShortcutsActivity.run(.running(name: name)))

        runTask = Task { [weak self, runner] in
            let outcome = await runner.run(name)
            guard !Task.isCancelled else { return }
            self?.finished(name, outcome)
        }
    }

    private func finished(_ name: String, _ outcome: ShortcutOutcome) {
        runningName = nil
        runTask = nil
        guard isActive else { return }
        island.submit(ShortcutsActivity.run(.finished(name: name, outcome: outcome)))
    }

    // MARK: - Library and favourites

    /// Reads the Shortcuts library. Only when asked — the settings pane
    /// appearing, or its refresh button — never on a schedule.
    func refreshLibrary() {
        guard isActive, libraryTask == nil else { return }
        isReadingLibrary = true

        libraryTask = Task { [weak self, runner] in
            let names = await runner.library()
            guard !Task.isCancelled else { return }
            self?.libraryRead(names)
        }
    }

    private func libraryRead(_ names: [String]) {
        library = names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        isReadingLibrary = false
        libraryTask = nil
    }

    func setFavourite(_ name: String, _ isFavourite: Bool) {
        var updated = favourites
        if isFavourite {
            updated.add(name)
        } else {
            updated.remove(name)
        }
        save(updated)
    }

    func moveFavourite(_ name: String, by offset: Int) {
        var updated = favourites
        updated.move(name, by: offset)
        save(updated)
    }

    private func save(_ updated: ShortcutFavourites) {
        favourites = updated
        Defaults[.shortcutFavourites] = updated
    }
}
