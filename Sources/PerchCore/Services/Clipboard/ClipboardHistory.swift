import Foundation

/// The clipboard's history, and every rule about it.
///
/// Pure: no pasteboard, no filesystem, no clock it does not own. Retention,
/// deduplication, pinning, exclusion and search all live here, which is why
/// the whole of `TEST-PLAN.md` § CLP is fast unit tests rather than a person
/// copying things and looking at a list (`CLAUDE.md` §3).
public struct ClipboardHistory: Equatable, Sendable, Codable {

    /// How much to keep.
    ///
    /// NotchBay caps its tray at 60 and does not let you change it. Ours
    /// defaults to 200 and does (`docs/FEATURES.md` §3).
    public struct Retention: Equatable, Sendable, Codable {
        public var maximumCount: Int
        public var maximumAge: Duration?

        public static let `default` = Self(
            maximumCount: 200,
            maximumAge: .seconds(7 * 24 * 60 * 60)
        )

        public init(maximumCount: Int = 200, maximumAge: Duration? = nil) {
            self.maximumCount = maximumCount
            self.maximumAge = maximumAge
        }
    }

    public private(set) var entries: [ClipboardEntry] = []
    public var retention: Retention

    public init(
        entries: [ClipboardEntry] = [],
        retention: Retention = .default
    ) {
        self.entries = entries
        self.retention = retention
        sort()
    }

    public var isEmpty: Bool { entries.isEmpty }
    public var count: Int { entries.count }

    /// Everything pinned, newest first. Drawn above the rest.
    public var pinned: [ClipboardEntry] { entries.filter(\.isPinned) }

    // MARK: - Recording

    /// Records a copy.
    ///
    /// - Returns: `true` if this was new. A repeat of what is already on top
    ///   moves its timestamp and returns `false`, so the caller knows not to
    ///   announce it (TC-CLP-002).
    @discardableResult
    public mutating func record(
        _ entry: ClipboardEntry,
        now: Date = .now
    ) -> Bool {
        if let index = entries.firstIndex(where: { $0.isDuplicate(of: entry) }) {
            entries[index].copiedAt = entry.copiedAt
            // A duplicate never un-pins what was already pinned, and never
            // loses OCR text that has already been done.
            if entries[index].recognisedText == nil {
                entries[index].recognisedText = entry.recognisedText
            }
            sort()
            return false
        }

        // Inserted in place rather than appended and re-sorted. A copy
        // arrives newest, so this is a walk past the pinned block and no
        // more — re-sorting the whole history on every copy is the kind of
        // cost that only shows up once somebody has ten thousand clips.
        let insertion =
            entries.firstIndex { !$0.isPinned && $0.copiedAt <= entry.copiedAt }
            ?? entries.count
        entries.insert(entry, at: insertion)

        prune(now: now)
        return true
    }

    /// Attaches OCR text to an entry after the fact.
    ///
    /// Recognition is slow enough to be worth doing off the critical path, so
    /// the entry lands first and gains its text a moment later (TC-CLP-012).
    public mutating func attachRecognisedText(_ text: String?, to id: ClipboardEntry.ID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        // Nothing found is a legitimate result and is recorded as such, so
        // the module does not try again forever (TC-CLP-013).
        entries[index].recognisedText = text
    }

    // MARK: - Mutation

    public mutating func togglePin(_ id: ClipboardEntry.ID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].isPinned.toggle()
        sort()
    }

    @discardableResult
    public mutating func remove(_ id: ClipboardEntry.ID) -> ClipboardEntry? {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return nil }
        return entries.remove(at: index)
    }

    /// Clears everything unpinned. Pinned entries are the point of pinning.
    public mutating func clearUnpinned() {
        entries.removeAll { !$0.isPinned }
    }

    public mutating func removeAll() {
        entries.removeAll()
    }

    // MARK: - Search

    /// Filters as you type.
    ///
    /// Case- and diacritic-insensitive substring matching over everything the
    /// entry can be found by. Not fuzzy: people search their clipboard for a
    /// string they know they copied, and fuzzy matching on 10,000 entries
    /// returns the wrong thing first (TC-CLP-010).
    public func search(_ query: String) -> [ClipboardEntry] {
        let needle =
            query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !needle.isEmpty else { return entries }

        return entries.filter { $0.searchableText.contains(needle) }
    }

    // MARK: - Retention

    /// Applies the retention rules.
    ///
    /// Pinned entries are exempt from both, always. Someone who pinned
    /// something meant it (TC-CLP-005).
    public mutating func prune(now: Date = .now) {
        if let age = retention.maximumAge {
            let cutoff = now.addingTimeInterval(-age.seconds)
            // Entries are newest-first, so only the tail can be too old.
            // Checking it first turns the common case — nothing to do — from
            // a walk of the whole history into one comparison.
            if let oldest = entries.last, !oldest.isPinned, oldest.copiedAt < cutoff {
                entries.removeAll { !$0.isPinned && $0.copiedAt < cutoff }
            }
        }

        // Same again for the count limit: below it, there is nothing to do.
        guard entries.count > retention.maximumCount else { return }

        let unpinnedAllowance = retention.maximumCount - pinned.count
        guard unpinnedAllowance >= 0 else { return }

        var kept = 0
        var survivors: [ClipboardEntry] = []
        for entry in entries {
            if entry.isPinned {
                survivors.append(entry)
            } else if kept < unpinnedAllowance {
                survivors.append(entry)
                kept += 1
            }
        }
        entries = survivors
    }

    /// Pinned first, then newest first.
    private mutating func sort() {
        entries.sort { lhs, rhs in
            if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
            return lhs.copiedAt > rhs.copiedAt
        }
    }
}
