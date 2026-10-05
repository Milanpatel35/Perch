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
    /// The letter that runs this from the keyboard (`HomeKeymap`), shown on
    /// the button so the keys are learnt by looking.
    var key: Character?
    let action: () -> Void

    init(
        title: LocalizedStringKey,
        symbol: String,
        help: String,
        key: Character? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.symbol = symbol
        self.help = help
        self.key = key
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                Text(title)
                if let key {
                    Text(String(key))
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .frame(minWidth: 13, minHeight: 13)
                        .background(RoundedRectangle(cornerRadius: 3).fill(.white.opacity(0.16)))
                        .foregroundStyle(.white.opacity(0.75))
                        .accessibilityHidden(true)
                }
            }
            .font(.system(size: 11, weight: .medium))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(.white.opacity(0.14)))
            .foregroundStyle(.white)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(Text(key.map { "\(help) — \($0)" } ?? help))
    }
}
