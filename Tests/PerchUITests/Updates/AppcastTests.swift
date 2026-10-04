import XCTest

/// Covers `TEST-PLAN.md` § UPD for the feed: `Scripts/appcast.sh` run
/// against releases written here rather than read from GitHub.
final class AppcastTests: XCTestCase {

    private let signed =
        "<!-- sparkle version=\"14\" shortVersion=\"0.13.0\" "
        + "edSignature=\"c2lnbmF0dXJl\" length=\"6735096\" -->"

    private func release(
        _ tag: String,
        body: String,
        draft: Bool = false,
        asset: String? = "Perch-unsigned.zip"
    ) -> [String: Any] {
        [
            "tagName": tag,
            "isDraft": draft,
            "publishedAt": "2026-10-04T05:00:00Z",
            "url": "https://github.com/Milanpatel35/Perch/releases/tag/\(tag)",
            "body": body,
            "assets": asset.map {
                [
                    [
                        "name": $0,
                        "url":
                            "https://github.com/Milanpatel35/Perch/releases/download/\(tag)/\($0)"
                    ]
                ]
            } ?? []
        ]
    }

    /// Runs the script and returns the feed it wrote.
    private func appcast(_ releases: [[String: Any]]) throws -> String {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("appcast-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let input = directory.appendingPathComponent("releases.json")
        let output = directory.appendingPathComponent("appcast.xml")
        try JSONSerialization.data(withJSONObject: releases).write(to: input)

        let script = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Scripts/appcast.sh")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script.path, output.path]
        process.environment = [
            "RELEASES_JSON": input.path, "PATH": "/usr/bin:/bin:/opt/homebrew/bin:/usr/local/bin"
        ]
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()

        XCTAssertEqual(process.terminationStatus, 0)
        return try String(contentsOf: output, encoding: .utf8)
    }

    // MARK: - TC-UPD-006

    func test_TC_UPD_006_aSignedBuildIsListedWithItsSignature() throws {
        let feed = try appcast([release("build-0.13.0", body: "Notes.\n\n" + signed)])

        XCTAssertTrue(feed.contains("<sparkle:version>14</sparkle:version>"))
        XCTAssertTrue(
            feed.contains("<sparkle:shortVersionString>0.13.0</sparkle:shortVersionString>"))
        XCTAssertTrue(feed.contains("sparkle:edSignature=\"c2lnbmF0dXJl\""))
        XCTAssertTrue(feed.contains("length=\"6735096\""))
        XCTAssertTrue(
            feed.contains(
                "url=\"https://github.com/Milanpatel35/Perch/releases/download/build-0.13.0/"))
        XCTAssertTrue(
            feed.contains("<sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>"))
        XCTAssertNoThrow(try XMLDocument(xmlString: feed))
    }

    /// Every build from before updates existed has no signature. Listing
    /// one would only produce an update Sparkle refuses to install.
    func test_TC_UPD_006_unsignedDraftAndArchiveLessReleasesAreLeftOut() throws {
        let feed = try appcast([
            release("build-0.12.0", body: "No signature here."),
            release("build-0.13.1", body: signed, draft: true),
            release("build-0.13.2", body: signed, asset: nil)
        ])

        XCTAssertFalse(feed.contains("<item>"))
        XCTAssertNoThrow(try XMLDocument(xmlString: feed), "an empty feed is still a feed")
    }

    func test_TC_UPD_006_notesCannotBreakTheFeed() throws {
        let feed = try appcast([
            release("build-0.13.0", body: "Fixes <b>&</b> \"quotes\".\n" + signed)
        ])
        XCTAssertNoThrow(try XMLDocument(xmlString: feed))
        XCTAssertEqual(feed.components(separatedBy: "<item>").count, 2)
    }
}
