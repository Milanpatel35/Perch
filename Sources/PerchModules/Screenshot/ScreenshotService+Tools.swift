import Foundation
import PerchCore

/// The capture tools: pick a colour, measure an area, scan a code.
///
/// Measure and scan take an area the same way a screenshot does, and their
/// capture is deleted as soon as it has been read — the answer is kept, not
/// the picture (TC-SCR-016, TC-SCR-017). The colour picker takes no capture
/// at all.
extension ScreenshotService {

    /// The system's colour loupe. No Screen Recording — the loupe reads the
    /// screen itself — so it works before any permission is given
    /// (TC-SCR-015).
    func pickColor() {
        guard isActive, !isCapturing else { return }
        island.send(.collapseRequested)

        system.tools.sampleColor { [weak self] color in
            guard let self, isActive, let color else { return }
            let text = color.string(in: configuration.colorFormat)
            system.copy(.text(text))
            say(.copiedColor(text: text, color: color))
        }
    }

    func measure(_ staged: URL) {
        guard let size = system.tools.measure(staged) else {
            return say(.failed(reason: String(localized: "The capture could not be read")))
        }
        let label = MeasuredArea.label(size)
        system.copy(.text(label))
        say(.measured(label))
    }

    func scanCode(in staged: URL) async {
        let codes = await system.tools.detectCodes(staged)
        guard isActive else { return }

        switch CodeAction.decide(codes) {
        case .none:
            say(.noCode)
        case .open(let url):
            system.tools.open(url)
            say(.openedLink(host: url.host ?? url.absoluteString))
        case .copy(let payload):
            system.copy(.text(payload))
            say(.copiedCode)
        }
    }
}
