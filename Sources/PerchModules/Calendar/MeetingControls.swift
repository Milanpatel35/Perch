import AppKit
import ApplicationServices
import Foundation
import PerchCore

/// Mute, camera and leave, driven through the meeting client's menu bar.
///
/// `docs/PLAN.md` §2.4 calls this the most technically awkward thing in the
/// phase and budgets for it breaking when a vendor ships an update. Two
/// decisions contain that:
///
/// - **The menu bar, never the window.** A meeting window is custom-drawn
///   controls that move every release; the menu bar is a titled list the
///   vendor cannot change without breaking its own keyboard shortcuts.
///   ADR 0006 records it.
/// - **State is read, never remembered.** Every call re-reads the menu, so
///   muting inside the meeting app and muting from the island can never
///   disagree (TC-CAL-009).
///
/// Everything that can fail resolves to a state the view can explain:
/// `needsAccessibility`, `notRunning` or `unsupported` (TC-CAL-011,
/// TC-CAL-012). Nothing here throws, and nothing here blocks for longer
/// than `messagingTimeout`.
@MainActor
final class MeetingControls {

    /// A client that is busy — rendering video, mid-reconnect — can take
    /// arbitrarily long to answer an AX query, and the default timeout is
    /// six seconds on the main thread. Half a second: the island would
    /// rather say "unavailable" than freeze (TC-CAL-011).
    private static let messagingTimeout: Float = 0.5

    /// Whether Accessibility has been granted. Never prompts.
    var isTrusted: Bool { AXIsProcessTrusted() }

    /// Asks for Accessibility, with the system prompt.
    ///
    /// Called when somebody presses a control for the first time — not when
    /// the module is switched on, and certainly not at launch. The calendar
    /// countdown is the module's main feature and works without this
    /// entirely (`CLAUDE.md` §5.3).
    @discardableResult
    func requestTrust() -> Bool {
        // The constant is a global `var` in the SDK headers, which Swift 6
        // reads as shared mutable state. Its value is a documented, stable
        // string, so it is spelled out rather than imported.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Reading

    /// What the controls can do for this meeting, right now.
    ///
    /// Cheap enough to call on every island refresh: it walks one menu of
    /// one app, and returns early in every case where it cannot.
    func state(for link: MeetingLink?) -> MeetingControlState {
        guard let link else { return MeetingControlState() }

        var state = MeetingControlState(availability: .noMeeting, service: link.service)

        guard
            let bundleID = link.service.bundleID,
            let vocabulary = MeetingVocabulary.vocabulary(for: link.service)
        else {
            // A browser meeting. There is nothing to drive, and saying so is
            // more honest than a disabled button with no explanation.
            return state
        }

        guard let app = runningApplication(bundleID: bundleID) else {
            state.availability = .notRunning
            return state
        }

        guard isTrusted else {
            state.availability = .needsAccessibility
            return state
        }

        guard let menu = callMenu(in: app, vocabulary: vocabulary) else {
            // The client is running but is not in a call, or its menus moved.
            // Both look the same from here and both mean the same thing to
            // the person reading the island: nothing to press.
            state.availability = .unsupported
            return state
        }

        let actions = Set(menu.map(\.action))
        state.availability = actions.isEmpty ? .unsupported : .available
        state.isMuted = MeetingVocabulary.isMuted(given: actions)
        state.isCameraOn = MeetingVocabulary.isCameraOn(given: actions)

        return state
    }

    // MARK: - Acting

    /// Presses the menu item for an action. Returns false when the item is
    /// not there, which the caller shows rather than pretending it worked.
    @discardableResult
    func perform(_ action: MeetingVocabulary.Action, for link: MeetingLink) -> Bool {
        guard
            let bundleID = link.service.bundleID,
            let vocabulary = MeetingVocabulary.vocabulary(for: link.service),
            let app = runningApplication(bundleID: bundleID),
            isTrusted,
            let menu = callMenu(in: app, vocabulary: vocabulary)
        else { return false }

        guard let item = menu.first(where: { $0.action == action })?.item else { return false }

        return AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
    }

    /// Toggles mute by pressing whichever of the pair the client is
    /// currently offering. Reading first is what keeps the two in step —
    /// there is no remembered state to get out of date (TC-CAL-008).
    @discardableResult
    func toggleMute(for link: MeetingLink) -> Bool {
        let state = state(for: link)
        guard let isMuted = state.isMuted else { return false }
        return perform(isMuted ? .unmute : .mute, for: link)
    }

    @discardableResult
    func toggleCamera(for link: MeetingLink) -> Bool {
        let state = state(for: link)
        guard let isCameraOn = state.isCameraOn else { return false }
        return perform(isCameraOn ? .stopVideo : .startVideo, for: link)
    }

    @discardableResult
    func leave(for link: MeetingLink) -> Bool {
        perform(.leave, for: link)
    }

    // MARK: - Accessibility plumbing

    /// One recognised menu item. A list rather than a dictionary keyed by
    /// element: two items can perform the same action, and an `AXUIElement`
    /// is an opaque handle rather than an identity worth hashing on.
    private struct MenuItem {
        let item: AXUIElement
        let action: MeetingVocabulary.Action
    }

    private func runningApplication(bundleID: String) -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
    }

    /// The in-call menu's items, each mapped to the action it performs.
    ///
    /// Returns `nil` when the call menu is not there at all, which is how
    /// "not in a meeting" is told apart from "in a meeting whose items
    /// Perch does not recognise".
    private func callMenu(
        in app: NSRunningApplication,
        vocabulary: MeetingVocabulary
    ) -> [MenuItem]? {
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, Self.messagingTimeout)

        guard
            let menuBar = copyElement(from: element, attribute: kAXMenuBarAttribute),
            let menus = copyElements(from: menuBar, attribute: kAXChildrenAttribute)
        else { return nil }

        for menu in menus {
            guard
                let title = copyString(from: menu, attribute: kAXTitleAttribute),
                vocabulary.isCallMenu(title)
            else { continue }

            // One more level down: a menu bar item owns a single menu, and
            // that menu owns the items. Skipping the intermediate element is
            // the mistake that makes this return an empty list on every app.
            guard
                let container = copyElements(from: menu, attribute: kAXChildrenAttribute)?.first,
                let items = copyElements(from: container, attribute: kAXChildrenAttribute)
            else { continue }

            return items.compactMap { item in
                guard
                    let itemTitle = copyString(from: item, attribute: kAXTitleAttribute),
                    let action = vocabulary.action(for: itemTitle),
                    isEnabled(item)
                else { return nil }
                return MenuItem(item: item, action: action)
            }
        }

        return nil
    }

    /// A greyed-out item is one the client is refusing right now — "Unmute"
    /// while the host has muted everyone, for instance. Pressing it does
    /// nothing, so it does not count as available.
    private func isEnabled(_ element: AXUIElement) -> Bool {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, kAXEnabledAttribute as CFString, &value)
                == .success,
            let number = value as? Bool
        else { return true }
        return number
    }

    private func copyElement(from element: AXUIElement, attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success
        else { return nil }
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        // swiftlint:disable:next force_cast
        return (value as! AXUIElement)
    }

    private func copyElements(from element: AXUIElement, attribute: String) -> [AXUIElement]? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success
        else { return nil }
        return value as? [AXUIElement]
    }

    private func copyString(from element: AXUIElement, attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success
        else { return nil }
        return value as? String
    }
}
