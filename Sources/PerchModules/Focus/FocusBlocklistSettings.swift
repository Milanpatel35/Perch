import AppKit
import PerchCore
import SwiftUI
import UniformTypeIdentifiers

/// The blocklist half of the Focus pane.
///
/// Observes the service rather than taking values, so a site added here
/// shows up here without the pane being rebuilt.
struct FocusBlocklistSettings: View {

    @ObservedObject var service: FocusService

    @State private var typedSite = ""
    @State private var siteWasRefused = false

    private var list: DistractionBlocklist { service.blocklist }

    private var sortedApps: [String] {
        list.apps.sorted { Self.name(of: $0) < Self.name(of: $1) }
    }

    var body: some View {
        appsSection
        sitesSection
        honestySection
    }

    // MARK: - Apps

    @ViewBuilder
    private var appsSection: some View {
        Section {
            Toggle("Hide these apps during a focus session", isOn: binding(\.blocksApps))

            ForEach(sortedApps, id: \.self) { bundleID in
                row(Self.name(of: bundleID), detail: bundleID) {
                    var updated = list
                    updated.apps.remove(bundleID)
                    service.setBlocklist(updated)
                }
            }

            HStack {
                Button("Add an app…", action: chooseApp)
                Spacer()
                suggestions(
                    DistractionBlocklist.suggestedApps.filter {
                        !list.apps.contains($0) && Self.isInstalled($0)
                    },
                    title: Self.name(of:)
                ) { bundleID in
                    var updated = list
                    updated.apps.insert(bundleID)
                    service.setBlocklist(updated)
                }
            }
        } header: {
            Text("Keep out of the way — apps")
        } footer: {
            Text(
                """
                Hidden when they come to the front, never quit — nothing is \
                lost, and ⌘-Tab brings one straight back. Browsers are never \
                hidden; their tabs are handled below.
                """
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Sites

    @ViewBuilder
    private var sitesSection: some View {
        Section {
            Toggle("Close these sites during a focus session", isOn: binding(\.blocksSites))

            ForEach(list.sites.sorted(), id: \.self) { site in
                row(site.host, detail: nil) {
                    var updated = list
                    updated.sites.remove(site)
                    service.setBlocklist(updated)
                }
            }

            HStack {
                TextField("reddit.com", text: $typedSite)
                    .onSubmit(addTypedSite)
                Button("Add", action: addTypedSite)
                    .disabled(typedSite.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if siteWasRefused {
                Text("That is not a web address.").font(.caption).foregroundStyle(.orange)
            }

            suggestions(
                DistractionBlocklist.suggestedSites.filter { !list.sites.contains($0) },
                title: \.host
            ) { site in
                var updated = list
                updated.sites.insert(site)
                service.setBlocklist(updated)
            }
        } header: {
            Text("Keep out of the way — sites")
        } footer: {
            Text(siteFooter)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var siteFooter: String {
        var text = String(
            localized: """
                A listed site in the front tab of Safari, Chrome, Edge, Brave, \
                Vivaldi or Opera goes blank. Subdomains count: reddit.com covers \
                old.reddit.com. macOS asks once per browser whether Perch may \
                read its front tab. Firefox and Arc do not let any app read \
                their tabs, so nothing happens in them.
                """)
        let refused = service.blocker.refusedBrowsers.sorted()
        if !refused.isEmpty {
            text +=
                " "
                + String(
                    localized: """
                        Refused for \(refused.formatted(.list(type: .and))) — allow it \
                        in System Settings ▸ Privacy & Security ▸ Automation.
                        """)
        }
        return text
    }

    private func addTypedSite() {
        guard let site = BlockedSite(typed: typedSite) else {
            siteWasRefused = true
            return
        }
        siteWasRefused = false
        typedSite = ""
        var updated = list
        updated.sites.insert(site)
        service.setBlocklist(updated)
    }

    // MARK: - Saying what it is

    @ViewBuilder
    private var honestySection: some View {
        Section {
            if service.blockedThisSession > 0 {
                LabeledContent("Kept away this session", value: "\(service.blockedThisSession)")
            }
            Text(
                """
                Only during a focus session — never on a break, never while \
                paused. This is a nudge, not a lock: it cannot stop an app \
                launching or a site loading, and it is not meant to.
                """
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Pieces

    private func row(_ title: String, detail: String?, remove: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
            if let detail, detail != title {
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: remove) {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("Remove \(title)"))
        }
    }

    @ViewBuilder
    private func suggestions<Item: Hashable>(
        _ items: [Item],
        title: @escaping (Item) -> String,
        add: @escaping (Item) -> Void
    ) -> some View {
        if !items.isEmpty {
            HStack(spacing: 6) {
                ForEach(items.prefix(5), id: \.self) { item in
                    Button("+ \(title(item))") { add(item) }
                        .buttonStyle(.borderless)
                        .font(.caption)
                }
            }
        }
    }

    private func binding(_ keyPath: WritableKeyPath<DistractionBlocklist, Bool>) -> Binding<Bool> {
        Binding(
            get: { list[keyPath: keyPath] },
            set: { value in
                var updated = list
                updated[keyPath: keyPath] = value
                service.setBlocklist(updated)
            }
        )
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        panel.prompt = String(localized: "Hide during focus")
        guard panel.runModal() == .OK else { return }

        var updated = list
        for url in panel.urls {
            if let bundleID = Bundle(url: url)?.bundleIdentifier { updated.apps.insert(bundleID) }
        }
        service.setBlocklist(updated)
    }

    private static func isInstalled(_ bundleID: String) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
    }

    /// The app's own name when it is installed, its identifier when not.
    private static func name(of bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return bundleID
        }
        return FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "")
    }
}
