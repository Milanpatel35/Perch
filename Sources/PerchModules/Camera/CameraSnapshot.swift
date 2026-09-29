import AppKit
import PerchCore

/// The one code path in the camera module that writes anything.
///
/// Kept apart from the rest of the service on purpose. TC-CAM-007 says no
/// frame reaches disk during a preview, and the cheapest way to keep that
/// true is for every line that can write one to be in a file by itself,
/// where a reviewer can see all of it at once.
extension CameraService {

    /// One image, written once, only when pressed (TC-CAM-010).
    ///
    /// **This is the only code path in the module that writes anything.**
    /// The preview has no output attached at all, so there is no frame for
    /// it to write even by accident (TC-CAM-007).
    ///
    /// The image is staged in a temporary file, offered to the shelf, and
    /// the stage is cleaned up either way — so exactly one image survives,
    /// in the shelf if it is on and in Pictures if it is not.
    func snapshot() {
        guard isPreviewing else { return }

        Task { [weak self] in
            guard let self, let image = await session.snapshot() else { return }
            guard isActive, let staged = write(image, to: stagingURL()) else { return }

            if onSnapshot?(staged) == true {
                // The shelf copies it into its own directory.
                try? FileManager.default.removeItem(at: staged)
                return
            }

            moveToPictures(staged)
        }
    }

    private func stagingURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(snapshotName())
    }

    private func snapshotName() -> String {
        "Perch-\(Int(now().timeIntervalSince1970)).png"
    }

    private func write(_ image: NSImage, to url: URL) -> URL? {
        guard
            let tiff = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiff),
            let data = bitmap.representation(using: .png, properties: [:])
        else { return nil }

        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    private func moveToPictures(_ staged: URL) {
        guard
            let directory = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)
                .first
        else { return }

        let destination = directory.appendingPathComponent(staged.lastPathComponent)
        try? FileManager.default.moveItem(at: staged, to: destination)
    }

}
