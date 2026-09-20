import AppKit
import PerchCore
import SwiftUI
import UniformTypeIdentifiers

/// One thing on the shelf.
///
/// Draggable straight back out into any app, with a menu for the things you
/// would otherwise open Finder for: share, AirDrop, convert, reveal, remove.
struct ShelfRow: View {

    let item: ShelfItem

    @EnvironmentObject private var modules: ModuleHost
    @State private var isHovered = false

    private var service: ShelfService? { modules.service(ShelfService.self) }

    var body: some View {
        HStack(spacing: 10) {
            icon

            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(item.isAvailable ? 1 : 0.4))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.4))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if isHovered {
                actions
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.white.opacity(isHovered ? 0.1 : 0.05))
        )
        .onHover { isHovered = $0 }
        // Drag straight back out into any app. The provider hands over
        // Perch's copy, so whatever receives it gets a real file and the
        // original is still where it started (TC-SHF-002).
        .onDrag { provider }
        .contextMenu { menu }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(item.name), \(subtitle)"))
    }

    // MARK: - Pieces

    private var icon: some View {
        Group {
            if let url = item.storedURL, item.isAvailable {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
            } else {
                Image(systemName: symbolName)
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .frame(width: 22, height: 22)
    }

    private var symbolName: String {
        switch item.kind {
        case .file: "doc"
        case .folder: "folder"
        case .text: "text.alignleft"
        case .image: "photo"
        }
    }

    private var subtitle: String {
        guard item.isAvailable else {
            // Not removed, and not silent about it. The file is gone from
            // underneath us and the row says so (TC-SHF-005).
            return String(localized: "No longer available")
        }
        switch item.kind {
        case .text: return String(localized: "Text clipping")
        case .image: return String(localized: "Image clipping")
        case .file, .folder: return item.byteCount.formattedByteCount
        }
    }

    private var provider: NSItemProvider {
        guard let url = item.storedURL, item.isAvailable else {
            return NSItemProvider(object: item.name as NSString)
        }
        return NSItemProvider(contentsOf: url) ?? NSItemProvider()
    }

    @ViewBuilder
    private var actions: some View {
        if item.isAvailable, item.storedURL != nil {
            RowButton(symbol: "square.and.arrow.up", label: "Share") { share() }
        }
        RowButton(symbol: "xmark", label: "Remove from shelf") {
            service?.remove(item.id)
        }
    }

    @ViewBuilder
    private var menu: some View {
        if item.isAvailable, let url = item.storedURL {
            Button("Share…") { share() }
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }

            let conversions = service?.conversions(for: item) ?? []
            if !conversions.isEmpty {
                Divider()
                ForEach(conversions) { conversion in
                    Button(conversion.title) {
                        service?.convert(item, using: conversion)
                    }
                }
            }
            Divider()
        }
        Button("Remove from Shelf") { service?.remove(item.id) }
    }

    /// Opens the system share sheet, which is where AirDrop lives — there is
    /// no separate AirDrop API, and there does not need to be
    /// (`docs/FEATURES.md` §2, TC-SHF-010).
    private func share() {
        guard let url = item.storedURL,
            let view = NSApp.keyWindow?.contentView ?? NSApp.windows.first?.contentView
        else { return }

        let picker = NSSharingServicePicker(items: [url])
        picker.show(
            relativeTo: view.bounds,
            of: view,
            preferredEdge: .minY
        )
    }
}

private struct RowButton: View {

    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.75))
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.white.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }
}
