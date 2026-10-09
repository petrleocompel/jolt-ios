import SwiftUI
import UserNotifications

/// Settings → Notifications. Answers "will a poke from a friend actually
/// reach this phone?" without needing a friend, a permission grant, or
/// anything to fire — the server sends the same alert + silent pair a poke
/// uses, and the phone confirms it back.
struct NotificationTestView: View {
    @State var viewModel: NotificationTestViewModel
    @Environment(AppDependencies.self) private var dependencies

    var body: some View {
        List {
            diagnosticsSection
            testSection
            if viewModel.outcome != nil || viewModel.errorMessage != nil {
                resultSection
            }
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            viewModel.apnsToken = dependencies.apnsToken
            await viewModel.refresh()
        }
        .onDisappear { viewModel.cancelPolling() }
    }

    // MARK: - Sections

    private var diagnosticsSection: some View {
        Section {
            LabeledContent("Permission", value: permissionSummary)
            if viewModel.authorization == .notDetermined {
                Button("Allow notifications") {
                    Task { await viewModel.requestAuthorization() }
                }
            } else if viewModel.authorization == .denied {
                Button("Open iOS Settings") {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    UIApplication.shared.open(url)
                }
            }
            LabeledContent("Registered with server", value: registrationSummary)
            if let host = dependencies.serverConfiguration?.baseURL.host() {
                LabeledContent("Server", value: host)
            }
            LabeledContent("Delivery", value: viewModel.pushRegistration.transport.displayName)
                .accessibilityIdentifier("pushTransportRow")
            if let serverId = viewModel.pushRegistration.serverId {
                LabeledContent("Server ID") {
                    Text(serverId)
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                }
            }
            if let problem = viewModel.pushRegistration.problem {
                Text(problem)
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("This device")
        } footer: {
            Text("A push has to clear all three: iOS must allow it, Apple must have a token for "
                + "this install, and the server must know that token belongs to your account. "
                + "Through a relay, the relay forwards it without being able to read it.")
        }
    }

    private var testSection: some View {
        Section {
            Toggle("Also fire it on my Pavlok", isOn: $viewModel.fireOnPavlok)
            if viewModel.fireOnPavlok {
                Picker("Kind", selection: $viewModel.stimulus.kind) {
                    ForEach(StimulusKind.allCases) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                VStack(alignment: .leading) {
                    Text("Intensity: \(viewModel.stimulus.intensity)%")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Slider(
                        value: Binding(
                            get: { Double(viewModel.stimulus.intensity) },
                            set: { viewModel.stimulus.intensity = Int($0) }
                        ),
                        in: 0...100,
                        step: 5
                    )
                }
            }
            Button {
                Task { await viewModel.send() }
            } label: {
                if viewModel.isSending {
                    ProgressView()
                } else {
                    Text("Send test notification")
                }
            }
            .disabled(viewModel.isSending)
            .accessibilityIdentifier("sendTestNotificationButton")
        } header: {
            Text("Test")
        } footer: {
            Text(viewModel.fireOnPavlok
                ? "Tests the whole chain, down to the wearable. Needs a connected Pavlok — and "
                    + "\"Do not disturb incoming pokes\" still applies, so it reports muted rather "
                    + "than firing while that's on."
                : "Sends a notification only. Nothing fires, so this works with no Pavlok nearby.")
        }
    }

    private var resultSection: some View {
        Section {
            if let message = viewModel.errorMessage {
                Text(message).foregroundStyle(.red)
            }
            if let outcome = viewModel.outcome {
                OutcomeRow(outcome: outcome)
            }
        } header: {
            Text("Result")
        }
    }

    // MARK: - Summaries

    private var permissionSummary: String {
        switch viewModel.authorization {
        case .authorized: return "Allowed"
        case .provisional: return "Quiet delivery"
        case .ephemeral: return "Temporary"
        case .denied: return "Denied"
        case .notDetermined: return "Not asked yet"
        @unknown default: return "Unknown"
        }
    }

    private var registrationSummary: String {
        if let device = viewModel.thisDevice {
            return "Yes (…\(device.tokenSuffix))"
        }
        return viewModel.apnsToken == nil ? "No token from Apple" : "Not registered"
    }
}

/// The one line that matters: did it arrive, and how fast.
private struct OutcomeRow: View {
    let outcome: NotificationTestViewModel.Outcome

    var body: some View {
        switch outcome {
        case .waiting:
            HStack {
                ProgressView()
                Text("Sent — waiting for it to arrive…")
            }
        case .delivered(let ack):
            VStack(alignment: .leading, spacing: 4) {
                Label(
                    "Arrived in \(String(format: "%.1f", Double(ack.elapsedMs) / 1000))s",
                    systemImage: "checkmark.circle.fill"
                )
                .foregroundStyle(.green)
                Text(detail(for: ack))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        case .rejected(let reason):
            VStack(alignment: .leading, spacing: 4) {
                Label("Apple rejected the push", systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
                Text("\(reason). Sign out and back in to register a fresh token.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        case .noConfirmation:
            VStack(alignment: .leading, spacing: 4) {
                Label("No confirmation", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Apple accepted it but nothing arrived. Notifications may be off for Jolt, "
                    + "or the server's APNs environment may not match this build.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        case .notConfigured:
            VStack(alignment: .leading, spacing: 4) {
                Label("Server can't send pushes", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("It has no Apple credentials, so it logged the push instead of delivering it. "
                    + "Pokes will reach you only while the app is open.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func detail(for ack: TestPushAck) -> String {
        let path: String = switch ack.path {
        case .alert: "you tapped the notification"
        case .foreground: "shown while the app was open"
        case .background: "woke the app silently"
        }
        guard let status = ack.status else { return path.prefix(1).capitalized + path.dropFirst() + "." }
        let fired: String = switch status {
        case .fired: "the stimulus fired"
        case .deviceNotConnected: "no Pavlok was connected, so nothing fired"
        case .muted: "\"Do not disturb incoming pokes\" is on, so nothing fired"
        case .notAllowed: "the stimulus wasn't allowed"
        case .pending: "the device hasn't reported back"
        }
        return "\(path.prefix(1).capitalized + path.dropFirst()) — \(fired)."
    }
}
