import SwiftUI

struct RemoteControlView: View {
    let viewModel: DeviceControlViewModel

    private var isConnected: Bool { viewModel.connectedDevice != nil }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    DeviceStatusCard(
                        device: viewModel.connectedDevice,
                        connectionState: viewModel.connectionState
                    )
                }

                if !isConnected {
                    Section {
                        disconnectedNotice
                    }
                }

                // One card per stimulus, as list rows rather than a hand-rolled
                // `ScrollView`: the rest of the app (Settings, Alarms, Button,
                // Diagnostics) is inset-grouped `List`, and reproducing that
                // chrome by hand drifts from it the moment iOS changes it.
                // Clearing the row background and insets leaves the card free
                // to draw itself.
                Section("Send a stimulus") {
                    ForEach(StimulusKind.allCases) { kind in
                        StimulusCard(
                            kind: kind,
                            isEnabled: isConnected,
                            config: viewModel.stimulusSettings[kind],
                            onSend: { viewModel.fire($0) },
                            onSave: { viewModel.saveStimulusConfig($0) }
                        )
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                }

                Section {
                    NavigationLink {
                        DeviceDiagnosticsView(viewModel: viewModel)
                    } label: {
                        Label("Device info & diagnostics", systemImage: "stethoscope")
                    }
                    NavigationLink {
                        ButtonConfigView(viewModel: viewModel)
                    } label: {
                        Label("Button configuration", systemImage: "button.horizontal.top.press")
                    }
                    Button(role: .destructive) {
                        viewModel.disconnect()
                    } label: {
                        Label("Disconnect", systemImage: "xmark.circle")
                    }
                    .disabled(!isConnected)
                    .accessibilityIdentifier("disconnectButton")
                }
            }
            .navigationTitle("Remote")
            .accessibilityIdentifier("remoteControlScreen")
            .safeAreaInset(edge: .bottom) { actionFeedback }
            .animation(.snappy, value: viewModel.lastActionMessage)
            .animation(.snappy, value: viewModel.lastError)
        }
    }

    /// Why the send buttons are dead, stated where the buttons are. The
    /// previous version showed a green "connected" tick unconditionally,
    /// including when nothing was connected.
    private var disconnectedNotice: some View {
        Label {
            Text("Connect your Pavlok to send a stimulus.")
                .foregroundStyle(.primary)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
        .font(.subheadline)
        .accessibilityIdentifier("disconnectedNotice")
    }

    /// Confirmation and errors share one slot: an error supersedes the
    /// success note, because if the write failed then "sent" is a lie.
    @ViewBuilder
    private var actionFeedback: some View {
        if let error = viewModel.lastError {
            InlineBanner(text: error, style: .error)
                .onTapGesture { viewModel.lastError = nil }
                .accessibilityIdentifier("errorFeedback")
                .accessibilityHint("Tap to dismiss")
        } else if let message = viewModel.lastActionMessage {
            InlineBanner(text: message, style: .success)
                .accessibilityIdentifier("actionFeedback")
        }
    }
}

/// Device identity, connection state and battery in one row.
private struct DeviceStatusCard: View {
    let device: PavlokDevice?
    let connectionState: DeviceConnectionState

    var body: some View {
        HStack(spacing: 12) {
            statusIcon
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(device?.name ?? "No device")
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let battery = device?.info.batteryLevelPercent {
                Label("\(battery)%", systemImage: batterySymbol(battery))
                    .font(.subheadline)
                    .foregroundStyle(battery <= 20 ? .red : .secondary)
                    .monospacedDigit()
                    .accessibilityLabel("Battery \(battery) percent")
            }
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("deviceStatusRow")
        .accessibilityElement(children: .combine)
    }

    /// A spinner while connecting or scanning — the subtitle alone reads as a
    /// static label, so a stalled connect looks identical to a live one.
    @ViewBuilder
    private var statusIcon: some View {
        switch connectionState {
        case .connecting, .scanning:
            ProgressView()
        default:
            Image(systemName: statusSymbol)
                .font(.title2)
                .foregroundStyle(statusTint)
        }
    }

    private var subtitle: String {
        switch connectionState {
        case .connected: return device?.family.displayName ?? "Connected"
        case .connecting: return "Connecting…"
        case .scanning: return "Scanning…"
        case .disconnected: return "Disconnected"
        case .failed(let reason): return reason
        }
    }

    private var statusSymbol: String {
        switch connectionState {
        case .connected: return "checkmark.circle.fill"
        case .connecting, .scanning: return "antenna.radiowaves.left.and.right"
        case .disconnected: return "circle.dashed"
        case .failed: return "exclamationmark.circle.fill"
        }
    }

    private var statusTint: Color {
        switch connectionState {
        case .connected: return .green
        case .connecting, .scanning: return .accentColor
        case .disconnected: return .secondary
        case .failed: return .red
        }
    }

    private func batterySymbol(_ percent: Int) -> String {
        switch percent {
        case ..<10: return "battery.0percent"
        case ..<35: return "battery.25percent"
        case ..<60: return "battery.50percent"
        case ..<85: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
}
