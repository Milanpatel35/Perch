import CoreGraphics
import Foundation

/// How the preview is drawn: shape, mirroring, size and opacity.
///
/// A value, and pure — the masks, the aspect ratios and the clamping are all
/// unit-testable without opening a camera, which matters more here than
/// anywhere else in the app. The module that owns the device (`CLAUDE.md`
/// §4) should have as little logic in it as possible.
public struct CameraPresentation: Equatable, Sendable, Codable {

    /// `docs/FEATURES.md` §9: strip, circle, rounded rect, full 16:9.
    public enum Shape: String, Equatable, Sendable, Codable, CaseIterable {
        /// As wide as the notch, cropped to a band. The one that reads as
        /// part of the island rather than a window stuck to it.
        case strip

        case circle
        case rounded
        case wide

        public var displayName: String {
            switch self {
            case .strip: String(localized: "Strip")
            case .circle: String(localized: "Circle")
            case .rounded: String(localized: "Rounded")
            case .wide: String(localized: "16:9")
            }
        }

        /// Width ÷ height. The preview is always filled and cropped to this,
        /// never letterboxed and never stretched — TC-CAM-004 is about
        /// distortion, and a squashed face is the failure it names.
        public var aspectRatio: Double {
            switch self {
            case .strip: 4.0
            case .circle: 1.0
            case .rounded: 4.0 / 3.0
            case .wide: 16.0 / 9.0
            }
        }

        /// Corner radius as a fraction of the shorter side. A circle is not
        /// a special case in the view; it is this at its limit.
        public var cornerFraction: Double {
            switch self {
            case .strip: 0.22
            case .circle: 0.5
            case .rounded: 0.14
            case .wide: 0.06
            }
        }
    }

    public var shape: Shape = .rounded

    /// Horizontal flip. On by default, because a mirror is what everybody
    /// means by "show me my camera" — `docs/FEATURES.md` §9 records it as a
    /// remembered toggle rather than a fixed choice.
    public var isMirrored = true

    /// The long edge of the preview, in points. Clamped by `setWidth`.
    public var width: Double = 260

    /// 0.25–1. Below a quarter the preview is a smudge, and somebody who
    /// scrolled past the end would have no way of knowing where it went.
    public var opacity: Double = 1

    /// Whether the preview is pinned as a floating pill rather than living
    /// in the island (`docs/FEATURES.md` §9, TC-CAM-005).
    public var isPinned = false

    /// Where the pinned pill sits, in screen points from the top-left of the
    /// screen that owns it. `nil` means "not placed yet" — the module
    /// centres it under the notch the first time.
    public var pinnedOrigin: CGPoint?

    public static let minimumWidth: Double = 160
    public static let maximumWidth: Double = 640

    public init() {}

    /// Height that keeps the shape's aspect ratio. The view never computes
    /// this itself, so the pinned pill and the island preview cannot end up
    /// disagreeing about the same shape.
    public var height: Double {
        width / shape.aspectRatio
    }

    public var size: CGSize {
        CGSize(width: width, height: height)
    }

    /// Clamped, because the width comes from a scroll wheel and a scroll
    /// wheel has no end stops (`docs/FEATURES.md` §9).
    public mutating func setWidth(_ value: Double) {
        width = min(max(value, Self.minimumWidth), Self.maximumWidth)
    }

    public mutating func setOpacity(_ value: Double) {
        opacity = min(max(value, 0.25), 1)
    }

    /// Resizes by a scroll delta. Proportional rather than absolute: the
    /// same flick moves a small preview a little and a large one a lot,
    /// which is what makes it feel like resizing rather than nudging.
    public mutating func resize(byScroll delta: Double) {
        setWidth(width * (1 + delta / 200))
    }
}

/// A capture device, flattened.
///
/// `AVCaptureDevice` is a class over hardware that can be unplugged between
/// two lines of code. Everything above the module works on this.
public struct CameraDevice: Equatable, Sendable, Identifiable, Hashable {

    public let id: String
    public let name: String

    /// A Continuity Camera can go away when the iPhone sleeps, which is a
    /// normal event rather than an error (TC-CAM-013). Worth saying out loud
    /// in the picker.
    public let isContinuity: Bool

    public let isBuiltIn: Bool

    public init(id: String, name: String, isContinuity: Bool = false, isBuiltIn: Bool = false) {
        self.id = id
        self.name = name
        self.isContinuity = isContinuity
        self.isBuiltIn = isBuiltIn
    }
}

/// Which device the module should open, given what is plugged in.
///
/// Pure, and separate from the module because it is the part that has rules:
/// the remembered choice wins if it is still there, the built-in camera is
/// the fallback, and an empty list is a legitimate answer rather than a
/// crash (TC-CAM-012).
public enum CameraSelection {

    public static func resolve(
        preferred: String?,
        from devices: [CameraDevice]
    ) -> CameraDevice? {
        if let preferred, let match = devices.first(where: { $0.id == preferred }) {
            return match
        }
        return devices.first(where: \.isBuiltIn) ?? devices.first
    }

    /// What to fall back to when the device in use disappears.
    ///
    /// The next one that is not the one that went. `nil` means there is
    /// nothing left, and the module collapses rather than holding an open
    /// session against no hardware (TC-CAM-012).
    public static func fallback(
        after lost: String,
        from devices: [CameraDevice]
    ) -> CameraDevice? {
        let remaining = devices.filter { $0.id != lost }
        return remaining.first(where: \.isBuiltIn) ?? remaining.first
    }
}
