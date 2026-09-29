import Foundation
import PerchCore

/// The camera preview, in the island.
///
/// **Held until withdrawn, and that is a privacy decision rather than a
/// presentation one.** A `timeToLive` would collapse the island while the
/// preview is still on screen and leave the module guessing at when the
/// device should close. The module withdraws it, and closing it is what
/// closes the camera (TC-CAM-006).
struct CameraActivity: IslandActivity {

    static let identifier = ActivityID("camera.preview")

    let id = Self.identifier
    let source: ModuleID = .camera

    /// Ambient. A mirror is something you opened on purpose; it has no
    /// business taking the island from a meeting that is starting.
    let priority: ActivityPriority = .ambient

    let timeToLive: Duration? = nil

    let presentation: CameraPresentation

    /// The device being shown, for the label and for the picker.
    let deviceName: String

    /// Set when the preview opened by itself before a meeting, so the view
    /// can say why the camera just came on. An unexplained green light is
    /// the single worst thing this module could do.
    let reason: Reason

    /// Why the preview is up.
    enum Reason: Equatable, Sendable {
        case opened
        case preCallCheck(eventTitle: String)
    }

    /// What went wrong, if anything. The preview draws the explanation in
    /// place rather than failing to appear — a camera that silently does not
    /// open reads as a broken app (TC-CAM-011, TC-CAM-012, TC-CAM-016).
    let failure: CameraSession.Failure?
}
