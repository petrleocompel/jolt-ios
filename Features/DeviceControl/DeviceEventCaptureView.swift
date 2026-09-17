import SwiftUI

/// What the device sent, unprompted, while Diagnostics was listening.
///
/// The command that fires a stimulus is the one piece of this protocol still
/// missing, and it is something the app has to *send* — so it can't be found
/// by reading. But the device's own firmware fires stimuli all the time
/// (button press, hand-detect, alarms) and reports what it did over its
/// notify characteristics. Watching that is the nearest thing to a Bluetooth
/// HCI capture without a second machine.
///
/// Read-only: the subscription is switched on and off by the "Listen for
/// device events" toggle in `DeviceDiagnosticsView`, which owns it so it
/// keeps running while this screen, Protocol lab or the Bluetooth log is
/// open.
struct DeviceEventCaptureView: View {
    /// Only drives the empty-state copy; this screen can't change it.
    let isListening: Bool

    @State private var log = BLEEventLog.shared

    /// The prefix `BluetoothCentralManager` gives captured notifications, so
    /// they can be picked out of connection chatter.
    static func isCapturedEvent(_ event: BLEEvent) -> Bool {
        event.message.hasPrefix("EVENT ")
    }

    private var events: [BLEEvent] {
        log.events.filter(Self.isCapturedEvent)
    }

    var body: some View {
        List {
            Section {
                if events.isEmpty {
                    Text(isListening ? "Nothing yet — press the button on your Pavlok." : "Not listening.")
                        .foregroundStyle(.secondary)
                }
                // Newest first: the press you just made is the one to read.
                ForEach(events.reversed()) { event in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.message.replacingOccurrences(of: "EVENT ", with: ""))
                            .font(.footnote.monospaced())
                        Text(event.time)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text("While listening, make the device act on its own: press its button, "
                    + "trigger hand-detect, or let an alarm fire. Whatever it reports appears here, "
                    + "in the device's own encoding.")
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
        .accessibilityIdentifier("deviceEventCaptureScreen")
    }
}
