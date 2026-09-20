import AVFoundation
import AppKit
import ImageIO
import PerchCore
import UniformTypeIdentifiers

/// Turns one file into another, using only what macOS already ships.
///
/// ImageIO for stills, AVFoundation for video. No ffmpeg, no bundled binary,
/// nothing extra to notarise — which is both why the catalogue in
/// `ShelfConversion` stops where it does and why this feature costs the
/// download nothing (`docs/FEATURES.md` §2).
///
/// Everything writes to a new file. The original is never touched, never
/// moved and never overwritten (TC-SHF-002).
enum FileConverter {

    /// Converts a file, returning the URL of the new one.
    ///
    /// Video runs off the main thread with progress, because a 2GB export
    /// must not freeze the island (TC-SHF-014).
    static func convert(
        _ source: URL,
        using conversion: ShelfConversion,
        into directory: URL,
        progress: (@MainActor @Sendable (Double) -> Void)? = nil
    ) async throws -> URL {
        let name = source.deletingPathExtension().lastPathComponent
        let destination = uniqueURL(
            named: name,
            extension: conversion.outputExtension,
            in: directory
        )

        if conversion.isVideo {
            try await exportVideo(source, to: destination, progress: progress)
        } else {
            try exportImage(source, to: destination, as: conversion)
        }

        return destination
    }

    // MARK: - Images

    private static func exportImage(
        _ source: URL,
        to destination: URL,
        as conversion: ShelfConversion
    ) throws {
        guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil),
            CGImageSourceGetCount(imageSource) > 0
        else {
            throw ShelfConversionError.unreadable(source.lastPathComponent)
        }

        guard let type = utType(for: conversion),
            let destinationRef = CGImageDestinationCreateWithURL(
                destination as CFURL,
                type.identifier as CFString,
                1,
                nil
            )
        else {
            throw ShelfConversionError.unsupportedType(source.lastPathComponent)
        }

        // Copying the source's properties across is what preserves EXIF
        // orientation — without it a photo taken sideways converts to a
        // sideways photo (TC-SHF-011).
        let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil)
        var options: [CFString: Any] = properties as? [CFString: Any] ?? [:]
        options[kCGImageDestinationLossyCompressionQuality] = 0.9

        CGImageDestinationAddImageFromSource(
            destinationRef,
            imageSource,
            0,
            options as CFDictionary
        )

        guard CGImageDestinationFinalize(destinationRef) else {
            throw ShelfConversionError.writeFailed(destination.lastPathComponent)
        }
    }

    private static func utType(for conversion: ShelfConversion) -> UTType? {
        switch conversion {
        case .heicToJPEG, .toJPEG: .jpeg
        case .toPNG: .png
        case .toHEIC: .heic
        case .movToMP4: .mpeg4Movie
        }
    }

    // MARK: - Video

    /// Main-actor confined because `AVAssetExportSession` is not `Sendable`
    /// and the progress ticker has to read it. Nothing blocks here: the
    /// session does its work on its own queues and this only awaits it.
    /// Image conversion is CPU work and deliberately stays off this actor.
    @MainActor
    private static func exportVideo(
        _ source: URL,
        to destination: URL,
        progress: (@MainActor @Sendable (Double) -> Void)?
    ) async throws {
        let asset = AVURLAsset(url: source)

        guard
            let session = AVAssetExportSession(
                asset: asset,
                presetName: AVAssetExportPresetHighestQuality
            )
        else {
            throw ShelfConversionError.unsupportedType(source.lastPathComponent)
        }

        session.outputURL = destination
        session.outputFileType = .mp4
        // The audio track has to survive; a silent video is not a conversion
        // (TC-SHF-012).
        session.shouldOptimizeForNetworkUse = true

        let ticker = Task {
            while !Task.isCancelled {
                progress?(Double(session.progress))
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
        defer { ticker.cancel() }

        await session.export()

        switch session.status {
        case .completed:
            return
        case .cancelled:
            throw ShelfConversionError.cancelled
        default:
            throw ShelfConversionError.writeFailed(destination.lastPathComponent)
        }
    }

    // MARK: - Naming

    /// A name that is not already taken.
    ///
    /// Converting the same file twice must produce `photo.jpg` and
    /// `photo 2.jpg`, never one silently replacing the other.
    static func uniqueURL(
        named name: String,
        extension ext: String,
        in directory: URL
    ) -> URL {
        var candidate = directory.appendingPathComponent("\(name).\(ext)")
        var suffix = 2

        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(name) \(suffix).\(ext)")
            suffix += 1
        }
        return candidate
    }
}
