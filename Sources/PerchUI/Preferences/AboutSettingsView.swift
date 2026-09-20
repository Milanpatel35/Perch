import SwiftUI

/// What Perch is, and the promise it makes.
///
/// The wording here matches the website and the README on purpose. If one
/// changes, all three change — this is the claim the whole project rests on.
struct AboutSettingsView: View {

    private var version: String {
        let marketing =
            Bundle.main
            .object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build =
            Bundle.main
            .object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return [marketing, build].compactMap { $0 }.joined(separator: " · ")
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "bird.fill")
                .font(.system(size: 42))
                .foregroundStyle(.primary)

            Text("Perch")
                .font(.title2.weight(.semibold))

            Text(version)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(
                """
                Free and open source. Every feature, forever. \
                No Pro tier, no licence key, no account, no telemetry.
                """
            )
            .multilineTextAlignment(.center)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: 380)

            Link(
                "Read the source",
                destination: URL(
                    string: "https://github.com/Milanpatel35/Perch"
                ) ?? URL(fileURLWithPath: "/")
            )
            .font(.callout)

            Spacer()
        }
        .padding(.top, 34)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
