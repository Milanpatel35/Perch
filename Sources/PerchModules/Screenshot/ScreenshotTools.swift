import AppKit
import CoreImage
import ImageIO
import PerchCore
import Vision

/// The capture tools' edges: the colour loupe, reading a capture's size,
/// finding codes in it, and opening a link. Tests replace all four.
@MainActor
struct ScreenshotTools {

    /// Shows the system's colour loupe and calls back with what was picked,
    /// or `nil` for Escape.
    var sampleColor: (@escaping @MainActor (SampledColor?) -> Void) -> Void

    /// The size of a capture in points, from its pixels and recorded density.
    var measure: (URL) -> CGSize?

    /// Every code Vision finds in a capture, on this Mac.
    var detectCodes: @Sendable (URL) async -> [DetectedCode]

    /// Opens a web address in the default browser.
    var open: (URL) -> Void

    static var live: Self {
        Self(
            sampleColor: { done in
                // The loupe the system's own colour panel uses. It reads the
                // screen under the pointer itself, so it needs no Screen
                // Recording permission (TC-SCR-015).
                NSColorSampler().show { color in
                    let picked = color?.usingColorSpace(.sRGB).map {
                        SampledColor(
                            red: Double($0.redComponent),
                            green: Double($0.greenComponent),
                            blue: Double($0.blueComponent)
                        )
                    }
                    MainActor.assumeIsolated { done(picked) }
                }
            },
            measure: { url in
                guard
                    let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                    let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                        as? [CFString: Any],
                    let width = properties[kCGImagePropertyPixelWidth] as? Int,
                    let height = properties[kCGImagePropertyPixelHeight] as? Int
                else { return nil }
                return MeasuredArea.points(
                    pixelWidth: width,
                    pixelHeight: height,
                    dpi: properties[kCGImagePropertyDPIWidth] as? Double
                )
            },
            detectCodes: { url in
                await Task.detached(priority: .userInitiated) { CodeReader.codes(in: url) }.value
            },
            open: { NSWorkspace.shared.open($0) }
        )
    }
}

/// Finds QR codes and barcodes — on this Mac, with no network path, like
/// the text recogniser.
enum CodeReader {

    static func codes(in url: URL) -> [DetectedCode] {
        let found = vision(url)
        return found.isEmpty ? coreImageQR(url) : found
    }

    /// Vision reads every symbology, QR and barcodes alike.
    private static func vision(_ url: URL) -> [DetectedCode] {
        let request = VNDetectBarcodesRequest()
        do {
            try VNImageRequestHandler(url: url, options: [:]).perform([request])
        } catch {
            return []
        }
        return (request.results ?? []).compactMap { observation in
            guard let payload = observation.payloadStringValue else { return nil }
            let box = observation.boundingBox
            return DetectedCode(payload: payload, area: Double(box.width * box.height))
        }
    }

    /// Core Image's QR detector, when Vision found nothing.
    ///
    /// Vision's current barcode model leans on graphics or Neural Engine
    /// acceleration, and where that is missing it returns nothing rather
    /// than an error — the macOS 14 CI machine read no code at all from an
    /// image macOS 15 read at once. This detector runs on the CPU. QR only,
    /// so Vision stays first for barcodes.
    static func coreImageQR(_ url: URL) -> [DetectedCode] {
        guard
            let image = CIImage(contentsOf: url),
            let detector = CIDetector(
                ofType: CIDetectorTypeQRCode,
                context: CIContext(options: [.useSoftwareRenderer: true]),
                options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]
            )
        else { return [] }

        let extent = image.extent
        guard extent.width > 0, extent.height > 0 else { return [] }
        return detector.features(in: image).compactMap { feature in
            guard let code = feature as? CIQRCodeFeature, let payload = code.messageString else {
                return nil
            }
            let share = (code.bounds.width * code.bounds.height) / (extent.width * extent.height)
            return DetectedCode(payload: payload, area: Double(share))
        }
    }
}
