import AppKit
import ApplicationServices
import Foundation
import PerchCore

/// Watches macOS draw notification banners, and reads them.
///
/// **There is no API for this.** macOS hands an app its own notifications
/// and nobody else's. The two ways in are the private `db2` database behind
/// Full Disk Access, and the banner itself through Accessibility.
/// ADR 0007 records why this is the second one.
///
/// The whole of it is: attach an `AXObserver` to the process that draws
/// banners, take `AXWindowCreated`, and read the static text out of the
/// window that appeared. Everything that can fail — no permission, a
/// process that is not running, a window shape macOS changed — resolves to
/// "nothing mirrored" rather than to an error (TC-NTF-008, TC-NTF-011).
@MainActor
final class NotificationWatcher {

    /// The process that draws banners. It is `UserNotificationCenter` on
    /// macOS 13 and `NotificationCenter` from 14 onwards; both have been
    /// seen on the same OS during an upgrade, so both are tried.
    private static let bannerHosts = [
        "com.apple.notificationcenterui",
        "com.apple.UserNotificationCenter"
    ]

    /// A banner that is still animating in has no text yet. Reading it one
    /// runloop later is the difference between a mirrored notification and
    /// an empty one.
    private static let settleDelay: Duration = .milliseconds(120)

    /// Same reasoning as the meeting controls: the island would rather
    /// mirror nothing than block the main thread on a busy process.
    private static let messagingTimeout: Float = 0.5

    var onNotification: ((MirroredNotification) -> Void)?

    private var observer: AXObserver?
    private var element: AXUIElement?
    private var launchObserver: NSObjectProtocol?

    /// The banner most recently read, kept so that a reply has something to
    /// type into. It is a handle into another process and goes stale the
    /// moment the banner leaves the screen — which is exactly why `reply`
    /// checks rather than assumes (TC-NTF-011).
    private var lastBanner: AXUIElement?

    var isTrusted: Bool { AXIsProcessTrusted() }

    @discardableResult
    func requestTrust() -> Bool {
        // A global `var` in the SDK headers, which Swift 6 reads as shared
        // mutable state. The value is documented and stable.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Lifecycle

    /// Starts watching. Returns false when Accessibility has not been
    /// granted or the banner process could not be found — both of which the
    /// settings pane shows rather than failing silently (TC-NTF-008).
    @discardableResult
    func start() -> Bool {
        guard isTrusted else { return false }
        guard observer == nil else { return true }

        observeRelaunch()
        return attach()
    }

    func stop() {
        if let observer {
            CFRunLoopRemoveSource(
                CFRunLoopGetMain(),
                AXObserverGetRunLoopSource(observer),
                .defaultMode
            )
        }
        observer = nil
        element = nil
        lastBanner = nil

        if let launchObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(launchObserver)
        }
        launchObserver = nil
    }

    /// The banner process is restarted by macOS after a crash, a log-out, or
    /// a Focus change. An observer attached to the old pid then watches
    /// nothing at all, silently — which looks exactly like "notifications
    /// stopped working" and is impossible to diagnose from the outside.
    private func observeRelaunch() {
        guard launchObserver == nil else { return }

        launchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            // Read out here, where the notification still is: an
            // `NSNotification` is not `Sendable` and must not cross into the
            // isolated block. A `String?` is.
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
            let bundleID = (app as? NSRunningApplication)?.bundleIdentifier

            MainActor.assumeIsolated {
                guard let bundleID, Self.bannerHosts.contains(bundleID) else { return }

                self?.observer = nil
                self?.element = nil
                _ = self?.attach()
            }
        }
    }

    private func attach() -> Bool {
        guard let app = bannerProcess() else { return false }

        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, Self.messagingTimeout)

        var created: AXObserver?
        let status = AXObserverCreate(app.processIdentifier, Self.callback, &created)
        guard status == .success, let created else { return false }

        let context = Unmanaged.passUnretained(self).toOpaque()
        let added = AXObserverAddNotification(
            created,
            element,
            kAXWindowCreatedNotification as CFString,
            context
        )
        guard added == .success else { return false }

        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(created),
            .defaultMode
        )

        self.observer = created
        self.element = element
        return true
    }

    private func bannerProcess() -> NSRunningApplication? {
        for bundleID in Self.bannerHosts {
            let matches = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            if let first = matches.first { return first }
        }
        return nil
    }

    /// C callback, so it cannot capture. The watcher comes back through the
    /// refcon pointer handed to `AXObserverAddNotification`.
    private static let callback: AXObserverCallback = { _, window, _, context in
        guard let context else { return }
        let watcher = Unmanaged<NotificationWatcher>.fromOpaque(context)
            .takeUnretainedValue()

        // The callback is delivered on the run loop the source was added
        // to, which is the main one — so this is isolated in fact, and the
        // compiler cannot see it because `AXUIElement` is a CF handle with
        // no `Sendable` conformance to lean on.
        nonisolated(unsafe) let banner = window

        MainActor.assumeIsolated {
            watcher.windowCreated(banner)
        }
    }

    // MARK: - Reading a banner

    private func windowCreated(_ window: AXUIElement) {
        Task { [weak self] in
            // Let it finish animating in; an empty banner is not a
            // notification.
            try? await Task.sleep(for: Self.settleDelay)
            guard let self, let parsed = read(window) else { return }
            lastBanner = window
            onNotification?(parsed)
        }
    }

    /// Turns a banner's element tree into a value.
    ///
    /// The shape is not documented and has changed across releases, so this
    /// does not walk a fixed path. It collects every `AXStaticText`
    /// descendant in order and assigns them by position, which survives the
    /// tree being re-nested — the thing that actually changes between macOS
    /// versions (TC-NTF-011).
    func read(_ window: AXUIElement) -> MirroredNotification? {
        var texts: [String] = []
        collectText(from: window, into: &texts, depth: 0)

        let lines =
            texts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard lines.count >= 2 else { return nil }

        // First line is the app, second the title, the rest the body. A
        // banner with a subtitle puts it third, which is indistinguishable
        // from a two-line body — so it is treated as body, because getting
        // that wrong loses text and getting it right gains a font weight.
        let appName = lines[0]
        let title = lines[1]
        let body = lines.dropFirst(2).joined(separator: " ")

        return MirroredNotification(
            id: UUID().uuidString,
            appName: appName,
            bundleID: bundleID(forAppNamed: appName),
            title: title,
            body: body,
            receivedAt: Date(),
            canReply: hasReplyField(in: window)
        )
    }

    /// Depth-limited on purpose. A banner is four or five levels deep; a
    /// runaway tree walk on the main actor is how an accessibility bug in
    /// somebody else's process becomes a beachball in ours.
    private func collectText(from element: AXUIElement, into texts: inout [String], depth: Int) {
        guard depth < 12, texts.count < 16 else { return }

        let isStaticText = role(of: element) == kAXStaticTextRole
        if isStaticText, let value = string(from: element, attribute: kAXValueAttribute) {
            texts.append(value)
        }

        for child in children(of: element) {
            collectText(from: child, into: &texts, depth: depth + 1)
        }
    }

    /// Whether the banner is offering a reply field. Only Messages and Mail
    /// do, and only sometimes (TC-NTF-010).
    private func hasReplyField(in window: AXUIElement) -> Bool {
        findTextField(in: window, depth: 0) != nil
    }

    func findTextField(in element: AXUIElement, depth: Int) -> AXUIElement? {
        guard depth < 12 else { return nil }

        let elementRole = role(of: element)
        if elementRole == kAXTextFieldRole || elementRole == kAXTextAreaRole {
            return element
        }

        for child in children(of: element) {
            if let found = findTextField(in: child, depth: depth + 1) { return found }
        }
        return nil
    }

    /// Best effort, and deliberately so: the banner names the app in the
    /// user's language, and there is no attribute carrying its identifier.
    /// A `nil` here means the notification mirrors but cannot be filtered by
    /// app — which is worth saying in the settings pane, not worth guessing.
    private func bundleID(forAppNamed name: String) -> String? {
        NSWorkspace.shared.runningApplications
            .first { $0.localizedName == name }?
            .bundleIdentifier
    }

    // MARK: - Replying

    /// Types a reply into the banner still on screen and sends it.
    ///
    /// Everything about this is conditional, and that is the design rather
    /// than a shortcoming: the banner may already have gone, macOS may have
    /// moved the field, and the app may never have offered one. Each of
    /// those returns false, which the island turns into "open the app"
    /// (TC-NTF-011). Nothing here retries, and nothing here waits.
    @discardableResult
    func reply(with text: String) -> Bool {
        guard isTrusted, !text.isEmpty, let banner = lastBanner else { return false }
        guard let field = findTextField(in: banner, depth: 0) else { return false }

        let set = AXUIElementSetAttributeValue(
            field,
            kAXValueAttribute as CFString,
            text as CFTypeRef
        )
        guard set == .success else { return false }

        // Sending is a press on the field's default button where the banner
        // has one, and a confirm on the field itself where it does not —
        // Messages and Mail have differed on this between releases.
        if let send = findButton(titled: ["Send", "Reply"], in: banner, depth: 0) {
            return AXUIElementPerformAction(send, kAXPressAction as CFString) == .success
        }

        return AXUIElementPerformAction(field, kAXConfirmAction as CFString) == .success
    }

    private func findButton(
        titled titles: [String],
        in element: AXUIElement,
        depth: Int
    ) -> AXUIElement? {
        guard depth < 12 else { return nil }

        let title =
            role(of: element) == kAXButtonRole
            ? string(from: element, attribute: kAXTitleAttribute)
            : nil

        if let title, titles.contains(where: { $0.caseInsensitiveCompare(title) == .orderedSame }) {
            return element
        }

        for child in children(of: element) {
            if let found = findButton(titled: titles, in: child, depth: depth + 1) {
                return found
            }
        }
        return nil
    }

    // MARK: - AX plumbing

    private func role(of element: AXUIElement) -> String? {
        string(from: element, attribute: kAXRoleAttribute)
    }

    private func children(of element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value)
                == .success
        else { return [] }
        return value as? [AXUIElement] ?? []
    }

    private func string(from element: AXUIElement, attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success
        else { return nil }
        return value as? String
    }
}
