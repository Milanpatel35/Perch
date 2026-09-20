import Foundation
import PerchCore

@testable import PerchUI

/// The content the website's feature shots are taken of.
///
/// Kept here rather than invented inside each test so the pictures are
/// consistent with each other, and so it is obvious at a glance that they are
/// demonstration data — nobody's real clipboard ends up on a marketing page
/// by accident.
extension NowPlayingSnapshot {
    static var demo: Self {
        Self(
            title: "Raga Yaman — Alap",
            artist: "Nikhil Banerjee",
            album: "Live at Rotterdam",
            progress: PlaybackProgress(
                elapsed: .seconds(247),
                rate: 1,
                asOf: .now,
                duration: .seconds(1_284)
            ),
            sourceBundleID: "com.apple.Music",
            sourceName: "Music"
        )
    }
}

extension [ShelfItem] {
    static var demo: Self {
        [
            ShelfItem(
                kind: .file,
                name: "Q3-contract.pdf",
                storedPath: "/tmp/Q3-contract.pdf",
                originalPath: "/Users/you/Desktop/Q3-contract.pdf",
                byteCount: 2_411_000,
                addedAt: .now
            ),
            ShelfItem(
                kind: .file,
                name: "logo-mark.svg",
                storedPath: "/tmp/logo-mark.svg",
                originalPath: "/Users/you/Desktop/logo-mark.svg",
                byteCount: 18_400,
                addedAt: .now.addingTimeInterval(-40)
            ),
            ShelfItem(
                kind: .folder,
                name: "Release notes",
                storedPath: "/tmp/Release notes",
                originalPath: "/Users/you/Desktop/Release notes",
                byteCount: 96_000,
                addedAt: .now.addingTimeInterval(-90)
            )
        ]
    }
}

extension [ClipboardEntry] {
    static var demo: Self {
        [
            ClipboardEntry(
                kind: .text,
                text: "git switch -c feature/2-3-huds",
                copiedAt: .now,
                isPinned: true
            ),
            ClipboardEntry(
                kind: .color,
                text: "#1B3A6B",
                payload: Data("27,58,107".utf8),
                plainText: "rgb(27, 58, 107)",
                copiedAt: .now.addingTimeInterval(-60)
            ),
            ClipboardEntry(
                kind: .image,
                text: "Image",
                payload: Data(),
                recognisedText: "Build succeeded — 178 tests, 0 failures",
                copiedAt: .now.addingTimeInterval(-180)
            ),
            ClipboardEntry(
                kind: .fileURL,
                text: "/Users/you/Perch/docs/FEATURES.md",
                copiedAt: .now.addingTimeInterval(-300)
            )
        ]
    }
}
