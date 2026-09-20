import Foundation
import PerchCore

/// What the conversion menu says, and what a refusal says.
///
/// Here rather than in `PerchCore`, for the reason issue #16 turned up:
/// `String(localized:)` resolves against the bundle of the module it is
/// written in, and `PerchCore` is a framework with no string catalog. English
/// held there could never be translated, however correctly it was spelled.
///
/// It is also `CLAUDE.md` §3 applied honestly. Core owns what a conversion
/// *is*; the interface owns what it is *called*.
extension ShelfConversion {

    /// What the menu item says.
    var title: String {
        switch self {
        case .heicToJPEG, .toJPEG: String(localized: "Convert to JPEG")
        case .toPNG: String(localized: "Convert to PNG")
        case .toHEIC: String(localized: "Convert to HEIC")
        case .movToMP4: String(localized: "Convert to MP4")
        }
    }
}

extension ShelfConversionError {

    /// What the island says when a conversion cannot be done.
    ///
    /// Readable, and about the file rather than about the framework: "not a
    /// silent no-op" is the whole of TC-SHF-013, and a refusal that says
    /// `Error Domain=NSCocoaErrorDomain Code=260` is a silent no-op with
    /// extra steps.
    var message: String {
        switch self {
        case .unsupportedType(let name):
            String(
                localized:
                    "Perch can't convert \(name). macOS has no converter for that format."
            )
        case .unreadable(let name):
            String(localized: "\(name) couldn't be read. It may be damaged or still downloading.")
        case .writeFailed(let name):
            String(localized: "\(name) couldn't be written. Check there is free space.")
        case .cancelled:
            String(localized: "Conversion cancelled.")
        }
    }
}
