import AppKit
import PerchCore
import SwiftUI

// MARK: - The "copied" acknowledgement

extension ClipboardActivity: IslandActivityPresenting {

    var peekSize: CGSize { CGSize(width: 320, height: 34) }
    var expandedSize: CGSize { CGSize(width: 380, height: 120) }

    func peekView() -> AnyView {
        AnyView(ClipboardPeek(entry: entry, historyCount: historyCount))
    }

    func expandedView() -> AnyView {
        AnyView(ClipboardPeek(entry: entry, historyCount: historyCount))
    }
}

private struct ClipboardPeek: View {

    let entry: ClipboardEntry
    let historyCount: Int

    @Environment(\.notchMetrics) private var metrics

    var body: some View {
        HStack(spacing: 0) {
            EntryGlyph(entry: entry, size: 20)
                .padding(.leading, 12)

            Spacer(minLength: metrics.collapsedSize.width)

            HStack(spacing: 6) {
                Text("Copied")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                Text("\(historyCount)")
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.black)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(.white))
            }
            .padding(.trailing, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Copied. \(historyCount) items in history."))
    }
}

// MARK: - The picker

extension ClipboardPickerActivity: IslandActivityPresenting {

    var peekSize: CGSize { CGSize(width: 340, height: 34) }

    var expandedSize: CGSize {
        CGSize(width: 480, height: 260)
    }

    func peekView() -> AnyView {
        AnyView(
            Text("Clipboard")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        )
    }

    func expandedView() -> AnyView {
        AnyView(ClipboardPicker(entries: entries))
    }
}

/// Type to filter, arrow keys to move, Enter to take it, ⌥-Enter for plain
/// text, Escape to dismiss (`docs/FEATURES.md` §3).
private struct ClipboardPicker: View {

    let entries: [ClipboardEntry]

    @EnvironmentObject private var modules: ModuleHost
    @State private var query = ""
    @State private var selection: ClipboardEntry.ID?
    @FocusState private var isSearchFocused: Bool

    private var service: ClipboardService? { modules.service(ClipboardService.self) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            searchField

            if entries.isEmpty {
                Text(query.isEmpty ? "Nothing copied yet." : "No matches.")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.45))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(entries) { entry in
                            ClipboardRow(
                                entry: entry,
                                isSelected: entry.id == selection
                            )
                            .onTapGesture { take(entry) }
                        }
                    }
                }
            }

            hints
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            isSearchFocused = true
            selection = entries.first?.id
        }
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.45))

            TextField("Search your clipboard", text: queryBinding)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(.white)
                .focused($isSearchFocused)
                .onSubmit { if let entry = selected { take(entry) } }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.1))
        )
    }

    private var hints: some View {
        HStack(spacing: 12) {
            Hint(key: "↩", label: "paste")
            Hint(key: "⌥↩", label: "plain text")
            Hint(key: "esc", label: "close")
            Spacer()
            Text("\(entries.count)")
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(.white.opacity(0.35))
        }
    }

    private var selected: ClipboardEntry? {
        entries.first { $0.id == selection } ?? entries.first
    }

    /// Filtering happens in the service, so the list the island shows is the
    /// list the service searched — no second copy to drift out of step.
    private var queryBinding: Binding<String> {
        Binding(
            get: { query },
            set: { newValue in
                query = newValue
                service?.updatePicker(query: newValue)
            }
        )
    }

    private func take(_ entry: ClipboardEntry) {
        service?.copyToPasteboard(
            entry,
            asPlainText: NSEvent.modifierFlags.contains(.option)
        )
    }
}

private struct Hint: View {
    let key: String
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.75))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.14))
                )
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.4))
        }
    }
}
