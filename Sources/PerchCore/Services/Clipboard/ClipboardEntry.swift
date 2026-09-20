import Foundation

/// One thing that was copied.
///
/// Module 3 of `docs/FEATURES.md`, and the single biggest gap in the paid
/// field — NotchNook is $25 and does not have this at all, and NotchBay caps
/// its tray at 60.
///
/// Pure Foundation: an entry knows what it is and how to be searched, and
/// nothing about `NSPasteboard`. That is what makes the retention, dedup,
/// exclusion and search rules unit tests rather than a thing you check by
/// copying something and looking.
public struct ClipboardEntry: Identifiable, Equatable, Sendable, Codable {

    public enum Kind: String, Sendable, Codable, CaseIterable {
        case text
        /// RTF and friends. Kept alongside a plain-text version so "paste as
        /// plain text" is a choice rather than a conversion (TC-CLP-015).
        case richText
        case image
        case fileURL
        /// A colour, which renders as a swatch rather than as its hex
        /// (TC-CLP-011).
        case color
    }

    public let id: UUID
    public let kind: Kind

    /// What the entry says, for display and for search. An image's text is
    /// whatever OCR found in it, if anything.
    public var text: String

    /// The original bytes, for kinds that have them.
    public var payload: Data?

    /// Plain-text fallback for rich text, so ⌥-paste has something to paste.
    public var plainText: String?

    /// Text found in an image by on-device OCR. Separate from `text` so it
    /// is clear where it came from, and so an image with no text is
    /// distinguishable from one that has not been read yet (TC-CLP-013).
    public var recognisedText: String?

    /// Bundle identifier of whatever was frontmost when this was copied.
    /// Used for the exclusion list and to show provenance.
    public var sourceBundleID: String?

    public var copiedAt: Date

    /// Pinned entries are never evicted, whatever the retention settings say
    /// (TC-CLP-005).
    public var isPinned: Bool

    public init(
        id: UUID = UUID(),
        kind: Kind,
        text: String,
        payload: Data? = nil,
        plainText: String? = nil,
        recognisedText: String? = nil,
        sourceBundleID: String? = nil,
        copiedAt: Date = .now,
        isPinned: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.payload = payload
        self.plainText = plainText
        self.recognisedText = recognisedText
        self.sourceBundleID = sourceBundleID
        self.copiedAt = copiedAt
        self.isPinned = isPinned
    }

    /// Everything this entry can be found by.
    ///
    /// A colour is searchable by both its hex and its RGB, because people
    /// remember one or the other and never reliably the one you stored
    /// (TC-CLP-011).
    var searchableText: String {
        [text, plainText, recognisedText]
            .compactMap { $0 }
            .joined(separator: "\n")
            .lowercased()
    }

    /// Whether two entries are the same copy.
    ///
    /// By content, not by id: copying the same thing twice is one entry with
    /// a newer timestamp, not two rows (TC-CLP-002).
    func isDuplicate(of other: Self) -> Bool {
        guard kind == other.kind else { return false }
        if let payload, let otherPayload = other.payload {
            return payload == otherPayload
        }
        return text == other.text
    }
}
