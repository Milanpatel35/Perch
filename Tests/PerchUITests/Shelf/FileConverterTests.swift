import AVFoundation
import AppKit
import CoreImage
import ImageIO
import PerchCore
import UniformTypeIdentifiers
import XCTest

@testable import PerchUI

/// Real conversions, on real files, written into a temporary directory.
///
/// Fixtures are generated here rather than committed: a checked-in HEIC is a
/// binary nobody reviews, and generating one proves ImageIO is doing the work
/// on both sides of the conversion.
@MainActor
final class FileConverterTests: XCTestCase {

    private var directory = URL(fileURLWithPath: NSTemporaryDirectory())

    override func setUp() async throws {
        try await super.setUp()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("perch-convert-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
        try await super.tearDown()
    }

    // MARK: - TC-SHF-011

    func test_TC_SHF_011_heicBecomesAValidJpeg() async throws {
        let source = try makeImage(named: "photo", type: .heic)

        let output = try await FileConverter.convert(
            source,
            using: .heicToJPEG,
            into: directory
        )

        XCTAssertEqual(output.pathExtension, "jpg")
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.path))

        // Valid, not merely present: ImageIO has to be able to read it back
        // and agree about what it is.
        let imageSource = try XCTUnwrap(CGImageSourceCreateWithURL(output as CFURL, nil))
        XCTAssertEqual(CGImageSourceGetType(imageSource) as String?, UTType.jpeg.identifier)
        XCTAssertNotNil(CGImageSourceCreateImageAtIndex(imageSource, 0, nil))
    }

    func test_TC_SHF_011_theOriginalIsUntouched() async throws {
        let source = try makeImage(named: "keepme", type: .png)
        let before = try Data(contentsOf: source)

        _ = try await FileConverter.convert(source, using: .toJPEG, into: directory)

        // TC-SHF-002's promise, enforced at the only place that could break
        // it: the original is copied from, never moved or rewritten.
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertEqual(try Data(contentsOf: source), before)
    }

    func test_TC_SHF_011_exifOrientationSurvivesTheConversion() async throws {
        let source = try makeImage(named: "sideways", type: .png, orientation: 6)

        let output = try await FileConverter.convert(
            source,
            using: .toJPEG,
            into: directory
        )

        let imageSource = try XCTUnwrap(CGImageSourceCreateWithURL(output as CFURL, nil))
        let properties =
            CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil)
            as? [CFString: Any]
        XCTAssertEqual(properties?[kCGImagePropertyOrientation] as? Int, 6)
    }

    func test_convertingTwiceNeverOverwritesTheFirstResult() async throws {
        let source = try makeImage(named: "twice", type: .png)

        let first = try await FileConverter.convert(source, using: .toJPEG, into: directory)
        let second = try await FileConverter.convert(source, using: .toJPEG, into: directory)

        XCTAssertNotEqual(first, second)
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
    }

    // MARK: - TC-SHF-012

    func test_TC_SHF_012_movBecomesAPlayableMp4() async throws {
        let source = try await makeSilentMovie(named: "clip")

        let output = try await FileConverter.convert(
            source,
            using: .movToMP4,
            into: directory
        )

        XCTAssertEqual(output.pathExtension, "mp4")

        let asset = AVURLAsset(url: output)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        XCTAssertFalse(tracks.isEmpty, "the MP4 has no video track")

        let duration = try await asset.load(.duration)
        XCTAssertGreaterThan(duration.seconds, 0)
    }

    func test_TC_SHF_012_noFfmpegIsLinked() {
        // The claim in FEATURES.md §2 is "ffmpeg-free". This is what that
        // means in practice: nothing but Apple's own frameworks is loaded.
        let suspects = ["ffmpeg", "libav", "avcodec", "avformat", "x264"]
        let loaded = (0..<_dyld_image_count()).compactMap {
            String(cString: _dyld_get_image_name($0)).lowercased()
        }

        for suspect in suspects {
            XCTAssertFalse(
                loaded.contains { $0.contains(suspect) },
                "\(suspect) is linked into the process"
            )
        }
    }

    // MARK: - TC-SHF-013

    func test_TC_SHF_013_anUnreadableFileIsRefusedWithSomethingReadable() async throws {
        let rubbish = directory.appendingPathComponent("broken.png")
        try Data([0x00, 0x01, 0x02]).write(to: rubbish)

        do {
            _ = try await FileConverter.convert(rubbish, using: .toJPEG, into: directory)
            XCTFail("a file that is not an image was converted anyway")
        } catch let error as ShelfConversionError {
            XCTAssertEqual(error, .unreadable("broken.png"))
            XCTAssertTrue(error.message.contains("broken.png"))
        }
    }

    // MARK: - Fixtures

    private func makeImage(
        named name: String,
        type: UTType,
        orientation: Int? = nil
    ) throws -> URL {
        let width = 64
        let height = 48
        let context = try XCTUnwrap(
            CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
            )
        )
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try XCTUnwrap(context.makeImage())

        let url = directory.appendingPathComponent(
            "\(name).\(type.preferredFilenameExtension ?? "png")")
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)
        )

        var properties: [CFString: Any] = [:]
        if let orientation { properties[kCGImagePropertyOrientation] = orientation }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)

        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }

    /// A one-second, video-only QuickTime file.
    ///
    /// Silent on purpose — writing an audio track here would test
    /// `AVAssetWriter` rather than the converter. "Audio track intact" is on
    /// the manual checklist, where a real recording can be used.
    private func makeSilentMovie(named name: String) async throws -> URL {
        let url = directory.appendingPathComponent("\(name).mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)

        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: 64,
                AVVideoHeightKey: 48
            ]
        )
        input.expectsMediaDataInRealTime = false

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB
            ]
        )

        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferCreate(nil, 64, 48, kCVPixelFormatType_32ARGB, nil, &pixelBuffer)
        let buffer = try XCTUnwrap(pixelBuffer)

        for frame in 0..<10 {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(5))
            }
            adaptor.append(
                buffer,
                withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 10)
            )
        }

        input.markAsFinished()
        await writer.finishWriting()
        return url
    }
}
