import AppKit
import ImageIO
import PerchCore

/// Reads the colour along the top edge of a screen's wallpaper, and says when
/// it may have changed.
///
/// **There is no public "wallpaper changed" event.** What there is: the file
/// macOS keeps the choice in, which it rewrites on every change, and a Space
/// switch, which can bring a different wallpaper with it. Both are push —
/// a kqueue on a directory and a workspace notification — so this costs
/// nothing between changes (`CLAUDE.md` §5.1). A spurious wake-up costs one
/// cache lookup, because colours are cached by image URL.
///
/// Only runs while the strip is set to match the wallpaper. With a black
/// strip there is nothing to re-match, and none of this exists.
@MainActor
final class WallpaperWatcher {

    /// Where the wallpaper choice lives. Sonoma moved it; Ventura is the
    /// floor this app supports, so both are watched and whichever exists
    /// wins. A directory rather than the file, because both are replaced
    /// rather than edited, and a descriptor on the old file goes deaf.
    private static var storeDirectories: [URL] {
        let support = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        return [
            support.appendingPathComponent("com.apple.wallpaper/Store", isDirectory: true),
            support.appendingPathComponent("Dock", isDirectory: true)
        ]
    }

    private var onChange: (@MainActor () -> Void)?
    private var sources: [DispatchSourceFileSystemObject] = []
    private var spaceObserver: NSObjectProtocol?
    private var colours: [URL: StripColor] = [:]

    var isWatching: Bool { onChange != nil }

    func start(onChange: @escaping @MainActor () -> Void) {
        guard !isWatching else { return }
        self.onChange = onChange

        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.onChange?() }
        }

        for directory in Self.storeDirectories {
            watch(directory)
        }
    }

    func stop() {
        if let spaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver)
        }
        spaceObserver = nil

        for source in sources {
            source.cancel()
        }
        sources = []

        colours = [:]
        onChange = nil
    }

    /// The top-edge colour of a screen's wallpaper, or `nil` if it cannot be
    /// read — a dynamic or video wallpaper whose URL is not an image. The
    /// caller falls back to black rather than guessing.
    func colour(for screen: NSScreen) -> StripColor? {
        guard let url = NSWorkspace.shared.desktopImageURL(for: screen) else { return nil }
        if let cached = colours[url] { return cached }

        let proportion = screen.frame.height > 0 ? screen.menuBarHeight / screen.frame.height : 0
        let colour = Self.topEdgeColour(of: url, proportion: max(proportion, 0.02))
        colours[url] = colour
        return colour
    }

    // MARK: - Internals

    private func watch(_ directory: URL) {
        guard FileManager.default.fileExists(atPath: directory.path) else { return }

        let descriptor = open(directory.path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete, .extend],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                // The same URL can hold a new picture, so a store change is
                // the one event that throws the cache away.
                self?.colours = [:]
                self?.onChange?()
            }
        }
        source.setCancelHandler {
            close(descriptor)
        }
        source.resume()

        sources.append(source)
    }

    /// Decodes a small thumbnail, never the full image. A 6K HEIC decoded
    /// whole on every Space switch would be the most expensive thing Perch
    /// does, for a colour.
    private static func topEdgeColour(of url: URL, proportion: Double) -> StripColor? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 256
        ]
        guard
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }

        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)

        let drew = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard
                let context = CGContext(
                    data: buffer.baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
                )
            else { return false }
            // Row 0 of a bitmap context's memory is the top of the image,
            // which is the edge wanted.
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drew else { return nil }

        let rows = Int((Double(height) * proportion).rounded(.up))
        return WallpaperEdge.averageColor(rgba: pixels, width: width, height: height, rows: rows)
    }
}

extension NSScreen {

    /// The menu bar's thickness on this screen, or zero when it has none —
    /// set to hide itself, or a second display without its own bar.
    var menuBarHeight: CGFloat {
        max(0, frame.maxY - visibleFrame.maxY)
    }

    /// A stable identity for a display, surviving unplug and replug — which
    /// `CGDirectDisplayID` does not. What per-display settings are keyed by.
    var displayUUID: String? {
        guard
            let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
            let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue()
        else { return nil }
        return CFUUIDCreateString(nil, uuid) as String?
    }
}
