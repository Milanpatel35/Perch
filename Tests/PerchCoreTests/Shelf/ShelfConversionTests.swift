import XCTest

@testable import PerchCore

/// TC-SHF-013 at the level where it is decidable: what the shelf offers, and
/// what it refuses to pretend it can do.
final class ShelfConversionTests: XCTestCase {

    // MARK: - TC-SHF-011

    func test_TC_SHF_011_aHEICPhotoCanBecomeAJPEG() {
        let offered = ShelfConversion.available(forFileNamed: "IMG_4021.heic")

        XCTAssertTrue(offered.contains { $0.outputExtension == "jpg" })
    }

    func test_TC_SHF_011_heifIsTheSameFormatByAnotherName() {
        XCTAssertFalse(ShelfConversion.available(forFileNamed: "photo.heif").isEmpty)
    }

    // MARK: - TC-SHF-012

    func test_TC_SHF_012_aMOVCanBecomeAnMP4() {
        let offered = ShelfConversion.available(forFileNamed: "screen-recording.mov")

        XCTAssertEqual(offered.map(\.outputExtension), ["mp4"])
        XCTAssertTrue(offered.allSatisfy(\.isVideo))
    }

    // MARK: - TC-SHF-013

    func test_TC_SHF_013_anUnsupportedTypeIsOfferedNothingAtAll() {
        // An empty menu, not a menu whose every item fails.
        XCTAssertTrue(ShelfConversion.available(forFileNamed: "archive.zip").isEmpty)
        XCTAssertTrue(ShelfConversion.available(forFileNamed: "notes.md").isEmpty)
        XCTAssertTrue(ShelfConversion.available(forFileNamed: "Keynote.app").isEmpty)
    }

    func test_TC_SHF_013_aFileWithNoExtensionIsOfferedNothing() {
        XCTAssertTrue(ShelfConversion.available(forFileNamed: "Makefile").isEmpty)
        XCTAssertTrue(ShelfConversion.available(forFileNamed: "").isEmpty)
    }

    func test_TC_SHF_013_everyRefusalNamesTheFileItRefused() {
        // What a refusal *says* moved to the interface layer (issue #16) and
        // is checked there — `String(localized:)` in a framework resolves
        // against that framework's bundle, so English held in Core could
        // never be translated. What Core still owes is the fact a person with
        // four files on the shelf needs: which one it was.
        XCTAssertEqual(ShelfConversionError.unsupportedType("archive.zip").fileName, "archive.zip")
        XCTAssertEqual(ShelfConversionError.unreadable("broken.heic").fileName, "broken.heic")
        XCTAssertEqual(ShelfConversionError.writeFailed("out.jpg").fileName, "out.jpg")

        // Cancelling is the one refusal that is not about a file.
        XCTAssertNil(ShelfConversionError.cancelled.fileName)
    }

    // MARK: - The menu itself

    func test_nothingIsEverOfferedAConversionIntoItsOwnFormat() {
        for name in ["photo.jpg", "photo.jpeg", "art.png", "clip.mp4", "shot.heic"] {
            let offered = ShelfConversion.available(forFileNamed: name)
            let ext = (name as NSString).pathExtension.lowercased()

            XCTAssertFalse(
                offered.contains { $0.outputExtension == ext },
                "\(name) was offered a conversion to what it already is"
            )
        }
    }

    func test_theMenuNeverOffersTheSameDestinationTwice() {
        for name in ["photo.heic", "art.png", "shot.tiff", "web.webp"] {
            let outputs = ShelfConversion.available(forFileNamed: name)
                .map(\.outputExtension)

            XCTAssertEqual(
                outputs.count,
                Set(outputs).count,
                "\(name) offered two routes to the same format"
            )
        }
    }

    func test_extensionMatchingIgnoresCase() {
        XCTAssertEqual(
            ShelfConversion.available(forFileNamed: "PHOTO.HEIC").map(\.outputExtension),
            ShelfConversion.available(forFileNamed: "photo.heic").map(\.outputExtension)
        )
    }
}
