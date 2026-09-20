import AppKit
import PerchCore
import SwiftUI

/// One entry in the picker.
struct ClipboardRow: View {

    let entry: ClipboardEntry
    let isSelected: Bool

    @EnvironmentObject private var modules: ModuleHost
    @State private var isHovered = false

    private var service: ClipboardService? { modules.service(ClipboardService.self) }

    var body: some View {
        HStack(spacing: 9) {
            EntryGlyph(entry: entry, size: 22)

            VStack(alignment: .leading, spacing: 1) {
                Text(entry.displayText)
                    .font(.system(size: 12))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if let detail = entry.detailText {
                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.4))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            if entry.isPinned || isHovered {
                Button {
                    service?.togglePin(entry.id)
                } label: {
                    Image(systemName: entry.isPinned ? "pin.fill" : "pin")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(entry.isPinned ? 0.9 : 0.5))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(entry.isPinned ? "Unpin" : "Pin"))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(isSelected ? 0.16 : (isHovered ? 0.09 : 0.04)))
        )
        .onHover { isHovered = $0 }
        .contextMenu {
            Button("Copy") { service?.copyToPasteboard(entry) }
            Button("Copy as plain text") {
                service?.copyToPasteboard(entry, asPlainText: true)
            }
            Divider()
            Button(entry.isPinned ? "Unpin" : "Pin") { service?.togglePin(entry.id) }
            Button("Delete") { service?.remove(entry.id) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(entry.displayText))
    }
}

/// The little square at the left of a row.
///
/// A colour renders as the colour, not as its hex — which is the point of
/// storing colours separately at all (TC-CLP-011).
struct EntryGlyph: View {

    let entry: ClipboardEntry
    let size: CGFloat

    var body: some View {
        Group {
            switch entry.kind {
            case .color:
                RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                    .fill(entry.swatchColor ?? .gray)
                    .overlay(
                        RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.25))
                    )

            case .image:
                if let payload = entry.payload, let image = NSImage(data: payload) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .clipShape(
                            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                        )
                } else {
                    glyph("photo")
                }

            case .fileURL:
                glyph("doc")
            case .richText:
                glyph("textformat")
            case .text:
                glyph("text.alignleft")
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private func glyph(_ symbol: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(Color.white.opacity(0.1))
            Image(systemName: symbol)
                .font(.system(size: size * 0.5))
                .foregroundStyle(.white.opacity(0.65))
        }
    }
}

extension ClipboardEntry {

    /// One line, whatever the entry is.
    var displayText: String {
        switch kind {
        case .image:
            recognisedText?.firstLine ?? String(localized: "Image")
        case .fileURL:
            (text as NSString).lastPathComponent
        default:
            text.firstLine
        }
    }

    /// The second line, when there is something worth saying.
    var detailText: String? {
        switch kind {
        case .color: plainText
        case .fileURL: (text as NSString).deletingLastPathComponent
        case .image:
            // Spelled out rather than as a ternary: SwiftLint reads
            // `String(localized:)` in a ternary as a void call and rejects it.
            if recognisedText == nil {
                String(localized: "Image")
            } else {
                String(localized: "Text found in image")
            }
        case .richText: String(localized: "Formatted text")
        case .text: nil
        }
    }

    /// The stored RGB, as a colour.
    var swatchColor: Color? {
        guard kind == .color, let payload,
            let components = String(data: payload, encoding: .utf8)?
                .split(separator: ",")
                .compactMap({ Double($0) }),
            components.count == 3
        else { return nil }

        return Color(
            red: components[0] / 255,
            green: components[1] / 255,
            blue: components[2] / 255
        )
    }
}

extension String {
    /// The first non-empty line, collapsed. A clipboard row is one line high.
    fileprivate var firstLine: String {
        let line = split(whereSeparator: \.isNewline).first.map(Self.init) ?? self
        return line.trimmingCharacters(in: .whitespaces)
    }
}
