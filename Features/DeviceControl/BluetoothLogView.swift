import SwiftUI

/// Live view of `BLEEventLog`.
///
/// Exists because "I pressed Zap and nothing happened, not even in the logs"
/// has to be answerable without Xcode attached. Everything the BLE layer
/// does — scan, discover, connect, every write and its acknowledgement —
/// lands here and can be shared out as text.
struct BluetoothLogView: View {
    @State private var log = BLEEventLog.shared

    var body: some View {
        List {
            if log.events.isEmpty {
                ContentUnavailableView(
                    "No Bluetooth activity yet",
                    systemImage: "dot.radiowaves.left.and.right",
                    description: Text("Connect a device or send a stimulus and it will show up here.")
                )
            }
            // Newest first: the thing you just did is the thing you want to
            // read, and it would otherwise be off the bottom of a long list.
            ForEach(log.events.reversed()) { event in
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.message)
                        .font(.footnote.monospaced())
                        .foregroundStyle(event.level == .error ? Color.red : Color.primary)
                    Text(event.timestamp, format: .dateTime.hour().minute().second())
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .listRowSeparator(.visible)
            }
        }
        .listStyle(.plain)
        .navigationTitle("Bluetooth log")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: log.transcript) {
                    Image(systemName: "square.and.arrow.up")
                }
                .disabled(log.events.isEmpty)
                .accessibilityLabel("Share log")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Clear") { log.clear() }
                    .disabled(log.events.isEmpty)
            }
        }
        .accessibilityIdentifier("bluetoothLogScreen")
    }
}
