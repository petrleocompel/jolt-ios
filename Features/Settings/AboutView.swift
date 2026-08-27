import SwiftUI

struct AboutView: View {
    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    var body: some View {
        List {
            Section {
                Text("Jolt is an independent iOS client for Pavlok wearables. Not affiliated with or endorsed by Pavlok Inc.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Section {
                LabeledContent("Version", value: version)
                Link("Privacy policy", destination: URL(string: "https://petrleocompel.github.io/jolt-ios/privacy/")!)
                Link("Support", destination: URL(string: "https://petrleocompel.github.io/jolt-ios/support/")!)
            }
        }
        .navigationTitle("About")
    }
}
