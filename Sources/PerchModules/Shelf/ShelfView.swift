import AppKit
import PerchCore
import SwiftUI
import UniformTypeIdentifiers

extension ShelfActivity: IslandActivityPresenting {

    var peekSize: CGSize { CGSize(width: 300, height: 34) }

    var expandedSize: CGSize {
        let rows = min(items.count, 4)
        return CGSize(width: 460, height: 96 + (CGFloat(rows) * 46))
    }

    func peekView() -> AnyView {
        AnyView(ShelfPeek(itemCount: items.count, isDropTarget: isDropTarget))
    }

    func expandedView() -> AnyView {
        AnyView(ShelfExpanded(items: items, isDropTarget: isDropTarget))
    }
}

// MARK: - Peek

private struct ShelfPeek: View {

    let itemCount: Int
    let isDropTarget: Bool

    @Environment(\.notchMetrics) private var metrics

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: isDropTarget ? "arrow.down.to.line" : "tray.full.fill")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.9))
                .padding(.leading, 12)

            Spacer(minLength: metrics.collapsedSize.width)

            // The stack badge (`docs/FEATURES.md` §2).
            Text("\(itemCount)")
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(.black)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Capsule().fill(.white))
                .padding(.trailing, 12)
                .opacity(itemCount == 0 ? 0 : 1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            Text(isDropTarget ? "Drop to add to the shelf" : "Shelf, \(itemCount) items")
        )
    }
}

// MARK: - Expanded

private struct ShelfExpanded: View {

    let items: [ShelfItem]
    let isDropTarget: Bool

    @EnvironmentObject private var modules: ModuleHost

    private var service: ShelfService? { modules.service(ShelfService.self) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            if isDropTarget {
                DropHint()
            } else if items.isEmpty {
                EmptyHint()
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(items) { item in
                            ShelfRow(item: item)
                        }
                    }
                }
            }

            if let conversion = service?.conversion {
                ConversionBar(progress: conversion)
            } else if let error = service?.lastError {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(nsColor: .systemRed))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Shelf")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)

            if !items.isEmpty {
                Text(items.totalBytes.formattedByteCount)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.45))
            }

            Spacer()

            if !items.isEmpty {
                Button("Clear") { service?.clearAll() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
    }
}

private struct DropHint: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(
                Color.white.opacity(0.45),
                style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])
            )
            .overlay(
                Label("Drop to hold", systemImage: "arrow.down.to.line")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct EmptyHint: View {
    var body: some View {
        Text("Drag a file to the notch and it waits here.")
            .font(.system(size: 12))
            .foregroundStyle(.white.opacity(0.45))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

private struct ConversionBar: View {

    let progress: ShelfService.ConversionProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Converting \(progress.itemName)…")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.6))
            ProgressView(value: progress.fraction)
                .progressViewStyle(.linear)
                .tint(.white)
        }
    }
}

extension [ShelfItem] {
    var totalBytes: Int64 { reduce(0) { $0 + $1.byteCount } }
}
