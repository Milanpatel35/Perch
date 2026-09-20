import AppKit
import PerchCore
import UniformTypeIdentifiers

/// Reads `NSPasteboard` and turns it into something Core understands.
///
/// Isolated here so `ClipboardHistory` never sees AppKit and every rule about
/// retention, dedup and exclusion stays a unit test.
@MainActor
enum PasteboardReader {

    /// The type password managers set to mean "do not record this".
    ///
    /// Honoured unconditionally — no setting, no override (TC-CLP-007).
    /// Both spellings are checked: the convention is the reverse-DNS one, and
    /// some apps still use the older bare name.
    static let concealedTypes: [NSPasteboard.PasteboardType] = [
        .init("org.nspasteboard.ConcealedType"),
        .init("org.nspasteboard.TransientType"),
        .init("com.agilebits.onepassword")
    ]

    static func isConcealed(_ pasteboard: NSPasteboard) -> Bool {
        guard let types = pasteboard.types else { return false }
        return concealedTypes.contains { types.contains($0) }
    }

    /// Builds an entry from whatever is on the pasteboard.
    ///
    /// Order matters, and it is richest-first. A copied file carries a file
    /// URL *and* a string; a copied colour carries a colour *and* a string.
    /// Reading the string first would flatten every one of them into text.
    static func entry(
        from pasteboard: NSPasteboard,
        sourceBundleID: String?
    ) -> ClipboardEntry? {
        guard !isConcealed(pasteboard) else { return nil }

        if let url = fileURL(from: pasteboard) {
            return ClipboardEntry(
                kind: .fileURL,
                text: url.path,
                payload: Data(url.path.utf8),
                sourceBundleID: sourceBundleID
            )
        }

        if let color = color(from: pasteboard) {
            return color.withSource(sourceBundleID)
        }

        let imageData = pasteboard.data(forType: .tiff) ?? pasteboard.data(forType: .png)
        if let image = imageData {
            return ClipboardEntry(
                kind: .image,
                text: String(localized: "Image"),
                payload: image,
                sourceBundleID: sourceBundleID
            )
        }

        if let rtf = pasteboard.data(forType: .rtf) {
            let plain = pasteboard.string(forType: .string) ?? ""
            return ClipboardEntry(
                kind: .richText,
                text: plain,
                payload: rtf,
                // Kept so "paste as plain text" is a choice rather than a
                // conversion done at paste time (TC-CLP-015).
                plainText: plain,
                sourceBundleID: sourceBundleID
            )
        }

        let string = pasteboard.string(forType: .string) ?? ""
        if !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return ClipboardEntry(
                kind: .text,
                text: string,
                sourceBundleID: sourceBundleID
            )
        }

        return nil
    }

    private static func fileURL(from pasteboard: NSPasteboard) -> URL? {
        guard
            let urls = pasteboard.readObjects(
                forClasses: [NSURL.self],
                options: [.urlReadingFileURLsOnly: true]
            ) as? [URL]
        else { return nil }
        return urls.first
    }

    /// A copied colour, rendered as a swatch and searchable by both its hex
    /// and its RGB — people remember one or the other, never reliably the one
    /// you stored (TC-CLP-011).
    private static func color(from pasteboard: NSPasteboard) -> ClipboardEntry? {
        guard
            let colors = pasteboard.readObjects(forClasses: [NSColor.self]) as? [NSColor],
            let color = colors.first?.usingColorSpace(.sRGB)
        else { return nil }

        let red = Int((color.redComponent * 255).rounded())
        let green = Int((color.greenComponent * 255).rounded())
        let blue = Int((color.blueComponent * 255).rounded())

        let hex = String(format: "#%02X%02X%02X", red, green, blue)
        let rgb = "rgb(\(red), \(green), \(blue))"

        return ClipboardEntry(
            kind: .color,
            text: hex,
            payload: Data("\(red),\(green),\(blue)".utf8),
            plainText: rgb
        )
    }

    /// Puts something back on the pasteboard.
    ///
    /// - Parameter asPlainText: strips formatting, for ⌥-select
    ///   (TC-CLP-015). The stored entry is untouched either way.
    static func write(_ entry: ClipboardEntry, asPlainText: Bool) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        switch entry.kind {
        case .richText where !asPlainText:
            if let payload = entry.payload {
                pasteboard.setData(payload, forType: .rtf)
            }
            pasteboard.setString(entry.plainText ?? entry.text, forType: .string)

        case .image:
            if let payload = entry.payload {
                pasteboard.setData(payload, forType: .tiff)
            }

        case .text, .richText, .fileURL, .color:
            pasteboard.setString(entry.plainText ?? entry.text, forType: .string)
        }
    }
}

extension ClipboardEntry {
    fileprivate func withSource(_ bundleID: String?) -> Self {
        var copy = self
        copy.sourceBundleID = bundleID
        return copy
    }
}
