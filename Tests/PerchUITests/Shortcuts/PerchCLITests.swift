import PerchCore
import XCTest

/// Covers TC-SHC-004: the `perch` CLI, end to end short of macOS opening the
/// URL. The real script, run the way a terminal runs it, with its URL read by
/// the real parser.
///
/// `PERCH_DRY_RUN=1` makes the script print the URL instead of opening it,
/// so the test launches nothing.
final class PerchCLITests: XCTestCase {

    /// The CLI, end to end short of macOS opening the URL: the real script,
    /// run the way a terminal runs it, and its URL read by the real parser.
    func test_TC_SHC_004_theCLIBuildsAURLThePerchParserAccepts() throws {
        let (status, output) = try runCLI(["notify", "build ok", "12s; $(whoami) & \"quoted\""])

        XCTAssertEqual(status, 0)
        let url = try XCTUnwrap(URL(string: output.trimmingCharacters(in: .whitespacesAndNewlines)))
        XCTAssertEqual(
            PerchURL.parse(url),
            .success(.notify(.init(title: "build ok", body: "12s; $(whoami) & \"quoted\"")))
        )
    }

    func test_TC_SHC_004_theCLIReadsItsMessageFromAPipe() throws {
        let (status, output) = try runCLI(
            ["notify", "--urgency", "high"], input: "Tests passed\nmore\n")

        XCTAssertEqual(status, 0)
        let url = try XCTUnwrap(URL(string: output.trimmingCharacters(in: .whitespacesAndNewlines)))
        XCTAssertEqual(
            PerchURL.parse(url),
            .success(.notify(.init(title: "Tests passed", urgency: .high)))
        )
    }

    func test_TC_SHC_004_theCLIRefusesNonsenseWithANonZeroExit() throws {
        XCTAssertEqual(try runCLI(["bogus"]).status, 64)
        XCTAssertEqual(try runCLI(["notify"], input: "").status, 64)
        XCTAssertEqual(try runCLI(["shelf", "/no/such/file"]).status, 66)
    }

    private func runCLI(
        _ arguments: [String], input: String? = nil
    ) throws -> (status: Int32, output: String) {
        let script = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../../../Resources/perch")
            .standardizedFileURL

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [script.path] + arguments
        process.environment = ["PERCH_DRY_RUN": "1", "PATH": "/usr/bin:/bin"]

        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        let stdin = Pipe()
        process.standardInput = stdin

        try process.run()
        if let input {
            stdin.fileHandleForWriting.write(Data(input.utf8))
        }
        try stdin.fileHandleForWriting.close()
        process.waitUntilExit()

        let data = output.fileHandleForReading.readDataToEndOfFile()
        return (process.terminationStatus, String(bytes: data, encoding: .utf8) ?? "")
    }
}
