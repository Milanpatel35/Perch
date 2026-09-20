import Foundation

/// The conversions the shelf offers, and for what.
///
/// The catalogue is here, in pure code, so "what can I do with this file"
/// is a unit test rather than a menu someone has to open. The conversion
/// itself needs ImageIO and AVFoundation and lives in the module.
///
/// Everything on this list is something macOS can already do. There is no
/// ffmpeg, no bundled binary and no helper to notarise — which is the reason
/// the list stops where it does rather than the reason to be apologetic
/// about it (`docs/FEATURES.md` §2).
public enum ShelfConversion: String, CaseIterable, Sendable, Identifiable {

    case heicToJPEG
    case toJPEG
    case toPNG
    case toHEIC
    case movToMP4

    public var id: String { rawValue }

    /// What the menu item says.
    public var title: String {
        switch self {
        case .heicToJPEG: "Convert to JPEG"
        case .toJPEG: "Convert to JPEG"
        case .toPNG: "Convert to PNG"
        case .toHEIC: "Convert to HEIC"
        case .movToMP4: "Convert to MP4"
        }
    }

    /// The extension the output gets.
    public var outputExtension: String {
        switch self {
        case .heicToJPEG, .toJPEG: "jpg"
        case .toPNG: "png"
        case .toHEIC: "heic"
        case .movToMP4: "mp4"
        }
    }

    /// Input extensions this conversion accepts, lowercased.
    var inputExtensions: Set<String> {
        switch self {
        case .heicToJPEG: ["heic", "heif"]
        case .toJPEG: ["png", "tiff", "tif", "webp", "gif", "bmp", "heic", "heif"]
        case .toPNG: ["jpg", "jpeg", "heic", "heif", "tiff", "tif", "webp", "gif", "bmp"]
        case .toHEIC: ["jpg", "jpeg", "png", "tiff", "tif"]
        case .movToMP4: ["mov", "m4v"]
        }
    }

    /// Whether this is a video conversion, which runs off the main thread and
    /// reports progress (TC-SHF-014).
    public var isVideo: Bool { self == .movToMP4 }

    /// Everything offered for a given file name.
    ///
    /// Empty means the shelf shows no conversion menu at all, rather than a
    /// menu whose every item fails (TC-SHF-013).
    public static func available(forFileNamed name: String) -> [Self] {
        let ext = (name as NSString).pathExtension.lowercased()
        guard !ext.isEmpty else { return [] }

        return
            allCases
            .filter { $0.inputExtensions.contains(ext) }
            // Never offer to convert a file into the format it already is.
            .filter { $0.outputExtension != normalised(ext) }
            // `heicToJPEG` and `toJPEG` both land on JPEG; keep one.
            .reduce(into: [Self]()) { result, conversion in
                guard
                    !result.contains(where: {
                        $0.outputExtension == conversion.outputExtension
                    })
                else { return }
                result.append(conversion)
            }
    }

    /// Collapses the spellings of one format so "convert a .jpeg to JPEG"
    /// never appears in the menu.
    private static func normalised(_ ext: String) -> String {
        switch ext {
        case "jpeg": "jpg"
        case "heif": "heic"
        case "tif": "tiff"
        default: ext
        }
    }
}

/// Why a conversion could not be done.
///
/// A refusal has to be readable — "not a silent no-op" is the whole of
/// TC-SHF-013.
public enum ShelfConversionError: Error, Equatable, Sendable {
    case unsupportedType(String)
    case unreadable(String)
    case writeFailed(String)
    case cancelled

    public var message: String {
        switch self {
        case .unsupportedType(let name):
            "Perch can't convert \(name). macOS has no converter for that format."
        case .unreadable(let name):
            "\(name) couldn't be read. It may be damaged or still downloading."
        case .writeFailed(let name):
            "\(name) couldn't be written. Check there is free space."
        case .cancelled:
            "Conversion cancelled."
        }
    }
}
