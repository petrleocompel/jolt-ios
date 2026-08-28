import SwiftUI

/// Subscribes to every notifying characteristic and shows what the device
/// sends, unprompted.
///
/// The command that fires a stimulus is the one piece of this protocol still
/// missing, and it is something the app has to *send* — so it can't be found
/// by reading. But the device's own firmware fires stimuli all the time
/// (button press, hand-detect, alarms) and reports what it did over its
/// notify characteristics. Watching that is the nearest thing to a Bluetooth
/// HCI capture without a second machine.
struct DeviceEventCaptureView: View {
    let viewModel: DeviceControlViewModel

    @State private var log = BLEEventLog.shared
    @State private var isListening = false
    @State private var subscribedCount = 0
    @State private var error: String?

    /// Only the lines this screen produced, so the instructions aren't
    /// buried under connection chatter.
    private var events: [BLEEvent] {
        log.events.filter { $0.message.hasPrefix("EVENT ") }
    }

    var body: some View {
        List {
            Section {
                if isListening {
                    Label("Listening on \(subscribedCount) characteristic\(subscribedCount == 1 ? "" : "s")",
                          systemImage: "dot.radiowaves.left.and.right")
                        .foregroundStyle(.green)
                    Button("Stop listening") {
                        viewModel.stopListeningForDeviceEvents()
                        isListening = false
                    }
                } else {
                    Button {
                        Task { await start() }
                    } label: {
                        Label("Start listening", systemImage: "antenna.radiowaves.left.and.right")
                    }
                    .accessibilityIdentifier("startListeningButton")
                }
                if let error {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
            } footer: {
                Text("With this running, make the device act on its own: press its button, "
                    + "trigger hand-detect, or let an alarm fire. Whatever it reports appears below, "
                    + "in the device's own encoding.")
            }

            Section("Captured events") {
                if events.isEmpty {
                    Text(isListening ? "Nothing yet — press the button on your Pavlok." : "Not listening.")
                        .foregroundStyle(.secondary)
                }
                ForEach(events.reversed()) { event in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.message.replacingOccurrences(of: "EVENT ", with: ""))
                            .font(.footnote.monospaced())
                        Text(event.timestamp, format: .dateTime.hour().minute().second())
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Device events")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: events.map(\.formatted).joined(separator: "\n")) {
                    Image(systemName: "square.and.arrow.up")
                }
                .disabled(events.isEmpty)
                .accessibilityLabel("Share captured events")
            }
        }
        // Subscriptions cost battery and keep the radio busy, so they don't
        // outlive the screen that asked for them.
        .onDisappear {
            viewModel.stopListeningForDeviceEvents()
            isListening = false
        }
        .accessibilityIdentifier("deviceEventCaptureScreen")
    }

    private func start() async {
        error = nil
        do {
            subscribedCount = try await viewModel.startListeningForDeviceEvents()
            isListening = subscribedCount > 0
            if subscribedCount == 0 { error = "No notifying characteristics could be subscribed." }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
