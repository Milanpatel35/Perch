import SwiftUI

/// One capsule on a home-surface row. Every row uses it — capture, tools,
/// the launcher — so the home surface reads as one set of buttons.
///
/// Five share a row, so the icon sits close to its word: a `Label` spaced
/// it too generously, and "Window" and "Screen" were cut to "Wind…" and
/// "Scre…".
struct HomeRowButton: View {

    let title: LocalizedStringKey
    let symbol: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: symbol)
                Text(title)
            }
            .font(.system(size: 11, weight: .medium))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(.white.opacity(0.14)))
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .help(Text(help))
    }
}
