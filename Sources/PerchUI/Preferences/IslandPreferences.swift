import Combine
import Defaults
import PerchCore

/// Carries the General pane's island settings to the things they control.
///
/// These switches were stored and shown, and read by nothing: "Island lives
/// on", "Expand on hover" and "Click to keep open" all did nothing whichever
/// way they were set. This is the missing wire — one place, event-driven,
/// applying each value now and again whenever it changes.
@MainActor
public final class IslandPreferences {

    private var cancellables: Set<AnyCancellable> = []

    public init(island: IslandController, panel: IslandPanelController) {
        Defaults.publisher(.hoverToExpand)
            .combineLatest(Defaults.publisher(.clickToPin))
            .map { hover, click in
                IslandGestures(hoverExpands: hover.newValue, clickPins: click.newValue)
            }
            .removeDuplicates()
            .sink { [weak island] gestures in
                island?.send(.gesturesChanged(gestures))
            }
            .store(in: &cancellables)

        Defaults.publisher(.islandScreenPolicy)
            .map { IslandPanelController.ScreenPolicy(rawValue: $0.newValue) ?? .builtIn }
            .removeDuplicates()
            .sink { [weak panel] policy in
                panel?.screenPolicy = policy
            }
            .store(in: &cancellables)
    }

    public func stop() {
        cancellables.removeAll()
    }
}
