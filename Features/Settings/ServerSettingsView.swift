import SwiftUI

/// Points the app at a Jolt Server — ours by default, or one you host.
///
/// Changing servers signs the user out: accounts, friends and poke history
/// all live on the instance that issued them, and none of it transfers.
struct ServerSettingsView: View {
    @Environment(AppDependencies.self) private var dependencies

    @State private var urlText = ""
    @State private var probe: ProbeState = .idle
    @State private var isConfirmingChange = false
    @State private var pendingConfiguration: ServerConfiguration?

    private let store = ServerSettingsStore()

    private enum ProbeState: Equatable {
        case idle
        case checking
        case reachable
        case failed(String)
    }

    private var parsed: Result<ServerConfiguration, ServerConfiguration.ValidationError> {
        ServerConfiguration.parse(urlText)
    }

    private var hasChanges: Bool {
        guard case .success(let config) = parsed else { return false }
        return config != store.load()
    }

    var body: some View {
        Form {
            Section {
                TextField("https://jolt.example.com/api/v1", text: $urlText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .font(.body.monospaced())
                    .accessibilityIdentifier("serverURLField")
                    .onChange(of: urlText) { _, _ in probe = .idle }
                statusRow
            } header: {
                Text("Server URL")
            } footer: {
                Text("Include the API path, usually /api/v1. "
                    + "Accounts don't transfer between servers — switching signs you out.")
            }

            Section {
                Button {
                    Task { await testConnection() }
                } label: {
                    HStack {
                        Text("Test connection")
                        if probe == .checking {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(isInvalid || probe == .checking)
                .accessibilityIdentifier("testConnectionButton")

                Button("Save and switch server") {
                    guard case .success(let config) = parsed else { return }
                    pendingConfiguration = config
                    isConfirmingChange = true
                }
                .disabled(!hasChanges)
                .accessibilityIdentifier("saveServerButton")
            }

            if store.isCustom {
                Section {
                    Button("Reset to default server", role: .destructive) {
                        pendingConfiguration = .default
                        isConfirmingChange = true
                    }
                } footer: {
                    Text("Default is \(ServerConfiguration.default.baseURL.absoluteString).")
                }
            }

            Section {
                Link(destination: URL(string: "https://github.com/petrleocompel/jolt-server")!) {
                    Label("How to host your own", systemImage: "book")
                }
            } footer: {
                Text("Jolt Server is open source. The repository's docs/SELFHOSTING.md walks through "
                    + "running one with Docker Compose.")
            }
        }
        .navigationTitle("Server")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { urlText = store.load().baseURL.absoluteString }
        .alert("Switch server?", isPresented: $isConfirmingChange) {
            Button("Cancel", role: .cancel) { pendingConfiguration = nil }
            Button("Switch", role: .destructive) { applyPendingConfiguration() }
        } message: {
            Text("You'll be signed out. Your friends and poke history stay on the old server.")
        }
    }

    private var isInvalid: Bool {
        if case .failure = parsed { return true }
        return false
    }

    @ViewBuilder
    private var statusRow: some View {
        switch probe {
        case .idle:
            if case .failure(let error) = parsed, !urlText.isEmpty {
                Label(error.localizedDescription, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        case .checking:
            Label("Checking…", systemImage: "ellipsis.circle")
                .font(.footnote)
                .foregroundStyle(.secondary)
        case .reachable:
            Label("Reachable — this is a Jolt server", systemImage: "checkmark.circle.fill")
                .font(.footnote)
                .foregroundStyle(.green)
        case .failed(let message):
            Label(message, systemImage: "xmark.circle.fill")
                .font(.footnote)
                .foregroundStyle(.red)
        }
    }

    private func testConnection() async {
        guard case .success(let config) = parsed else { return }
        probe = .checking
        switch await JoltAPIClient.probe(config) {
        case .success:
            probe = .reachable
        case .failure(let error):
            probe = .failed(error.localizedDescription)
        }
    }

    private func applyPendingConfiguration() {
        guard let pendingConfiguration else { return }
        store.save(pendingConfiguration)
        urlText = pendingConfiguration.baseURL.absoluteString
        probe = .idle
        self.pendingConfiguration = nil
        // The backend is built once at launch against a fixed base URL, so
        // the switch takes effect on next start. Saying so is better than
        // silently doing nothing until the user happens to relaunch.
        dependencies.pendingServerRestartNotice = true
    }
}
