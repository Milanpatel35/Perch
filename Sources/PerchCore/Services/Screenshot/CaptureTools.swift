import CoreGraphics
import Foundation

// The decisions inside the capture tools — what a colour is called, how big
// an area is, what a scanned code is allowed to do — kept apart from
// AppKit and Vision so they can be tested without a screen.

// MARK: - Colour

/// How a picked colour is written onto the clipboard.
public enum ColorFormat: String, CaseIterable, Sendable, Codable {
    case hex
    case rgb
    case hsl
}

/// A colour picked off the screen, in sRGB.
public struct SampledColor: Equatable, Sendable {

    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// `#1B3A6B` — upper case, as design tools and stylesheets write it.
    public var hex: String {
        String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
    }

    public var rgb: String {
        "rgb(\(byte(red)), \(byte(green)), \(byte(blue)))"
    }

    /// CSS's `hsl()`, in whole degrees and percentages (TC-SCR-014).
    public var hsl: String {
        let (red, green, blue) = (clamp(red), clamp(green), clamp(blue))
        let high = max(red, green, blue)
        let low = min(red, green, blue)
        let spread = high - low
        let lightness = (high + low) / 2

        guard spread > 0 else {
            // A grey has no hue and no saturation; writing one would be noise.
            return "hsl(0, 0%, \(percent(lightness))%)"
        }

        let saturation = spread / (1 - abs(2 * lightness - 1))
        var hue: Double
        switch high {
        case red: hue = ((green - blue) / spread).truncatingRemainder(dividingBy: 6)
        case green: hue = (blue - red) / spread + 2
        default: hue = (red - green) / spread + 4
        }
        hue *= 60
        if hue < 0 { hue += 360 }

        return "hsl(\(Int(hue.rounded()) % 360), \(percent(saturation))%, \(percent(lightness))%)"
    }

    public func string(in format: ColorFormat) -> String {
        switch format {
        case .hex: hex
        case .rgb: rgb
        case .hsl: hsl
        }
    }

    private func clamp(_ value: Double) -> Double { min(1, max(0, value)) }
    private func byte(_ value: Double) -> Int { Int((clamp(value) * 255).rounded()) }
    private func percent(_ value: Double) -> Int { Int((value * 100).rounded()) }
}

// MARK: - Measuring

/// The size of a measured area, in the points somebody would type into a
/// design tool or a `frame` — not the pixels the capture holds.
public enum MeasuredArea {

    /// `screencapture` records the display's density in the image: 72 DPI
    /// at 1x, 144 at 2x. Dividing by it is what makes a measurement on a
    /// Retina built-in and on a 1x external display agree (TC-SCR-016).
    public static func points(pixelWidth: Int, pixelHeight: Int, dpi: Double?) -> CGSize {
        let scale = max((dpi ?? 72) / 72, 1)
        return CGSize(
            width: (Double(pixelWidth) / scale).rounded(),
            height: (Double(pixelHeight) / scale).rounded()
        )
    }

    /// `1280 × 720`, which is what lands on the clipboard.
    public static func label(_ size: CGSize) -> String {
        "\(Int(size.width)) × \(Int(size.height))"
    }
}

// MARK: - Scanning

/// One code Vision found, and how much of the area it covered.
public struct DetectedCode: Equatable, Sendable {
    public var payload: String
    public var area: Double

    public init(payload: String, area: Double) {
        self.payload = payload
        self.area = area
    }
}

/// What a scanned code is allowed to do (TC-SCR-017).
public enum CodeAction: Equatable, Sendable {
    /// A web address, opened in the default browser.
    case open(URL)
    /// Anything else — text, a Wi-Fi password, a `mailto:`, another app's
    /// link — copied, and never opened. A code is a stranger's input: a
    /// scanner that opens whatever it reads is a way to make the Mac do
    /// things nobody chose.
    case copy(String)

    /// The largest code wins: an area taken around one code often catches a
    /// smaller one at its edge, and the one somebody aimed at is the big one.
    public static func decide(_ codes: [DetectedCode]) -> Self? {
        guard
            let chosen =
                codes
                .filter({ !$0.payload.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
                .max(by: { $0.area < $1.area })
        else { return nil }

        let payload = chosen.payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: payload), isWebAddress(url) else { return .copy(payload) }
        return .open(url)
    }

    private static func isWebAddress(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), let host = url.host else { return false }
        return (scheme == "http" || scheme == "https") && !host.isEmpty
    }
}
