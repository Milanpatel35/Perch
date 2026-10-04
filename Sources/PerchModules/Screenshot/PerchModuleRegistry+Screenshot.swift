import Foundation
import PerchCore
import SwiftUI

extension PerchModuleRegistry {

    /// A saved screenshot lands in the shelf when the shelf is on
    /// (`docs/FEATURES.md` §16). Returning false is how the screenshot
    /// module learns it is off, and uses the screenshot folder instead.
    @MainActor
    static func wireScreenshotToShelf(in host: ModuleHost) {
        host.service(ScreenshotService.self)?.onSave = { [weak host] url in
            guard let shelf = host?.service(ShelfService.self), shelf.isActive else { return false }
            return shelf.add(fileAt: url) != nil
        }
    }

    @MainActor
    static func screenshotPane(in host: ModuleHost) -> AnyView? {
        host.service(ScreenshotService.self).map { screenshot in
            AnyView(
                ScreenshotSettingsView(
                    service: screenshot,
                    isShelfOn: host.service(ShelfService.self)?.isActive ?? false,
                    screenshotFolder: screenshot.screenshotFolder
                )
            )
        }
    }
}
