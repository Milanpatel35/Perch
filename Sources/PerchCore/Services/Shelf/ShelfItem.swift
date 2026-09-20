import Foundation

/// One thing parked on the shelf.
///
/// Module 2 of `docs/FEATURES.md`. A shelf item is not the file — it is a
/// record *about* a file, plus the location of the copy Perch holds. That
/// distinction is the whole of TC-SHF-002 ("original untouched") and
/// TC-SHF-005 ("source file deleted while shelved").
public struct ShelfItem: Identifiable, Equatable, Sendable, Codable {

    public enum Kind: String, Sendable, Codable {
        case file
        /// A folder is one item, not its contents (TC-SHF-006).
        case folder
        /// A dragged text selection (TC-SHF-009).
        case text
        /// A dragged image selection.
        case image
    }

    public let id: UUID
    public var kind: Kind

    /// What the user sees. A file's name, or the first line of a clipping.
    public var name: String

    /// Where Perch's own copy lives, inside the container.
    ///
    /// Optional because a text clipping has no file until it is dragged back
    /// out, at which point one is written on demand.
    public var storedPath: String?

    /// Where it came from. Kept only to show provenance and to detect that
    /// the original has gone (TC-SHF-005) — never written to.
    public var originalPath: String?

    /// Inline payload for a clipping. Files are never held in memory.
    public var payload: Data?

    public var byteCount: Int64
    public var addedAt: Date

    /// False when Perch's copy has gone missing underneath it — someone
    /// emptied the container, or a sync client removed it. The row greys out
    /// rather than the app crashing on a dangling path (TC-SHF-005).
    public var isAvailable: Bool

    public init(
        id: UUID = UUID(),
        kind: Kind,
        name: String,
        storedPath: String? = nil,
        originalPath: String? = nil,
        payload: Data? = nil,
        byteCount: Int64 = 0,
        addedAt: Date = .now,
        isAvailable: Bool = true
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.storedPath = storedPath
        self.originalPath = originalPath
        self.payload = payload
        self.byteCount = byteCount
        self.addedAt = addedAt
        self.isAvailable = isAvailable
    }

    public var storedURL: URL? {
        storedPath.map { URL(fileURLWithPath: $0) }
    }
}

extension ShelfItem {

    /// Whether two records describe the same thing.
    ///
    /// Files compare by where they came from; clippings by their content.
    /// Identity cannot be the `id`, because a re-drop mints a new one.
    func isSameSource(as other: Self) -> Bool {
        guard kind == other.kind else { return false }

        switch kind {
        case .file, .folder:
            guard let mine = originalPath, let theirs = other.originalPath else {
                return false
            }
            return mine == theirs
        case .text, .image:
            return payload == other.payload
        }
    }
}
