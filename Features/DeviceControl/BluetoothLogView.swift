import SwiftUI
import UIKit

/// Live view of `BLEEventLog`.
///
/// Exists because "I pressed Zap and nothing happened, not even in the logs"
/// has to be answerable without Xcode attached. Everything the BLE layer
/// does — scan, discover, connect, every write and its acknowledgement —
/// lands here and can be copied or shared out as text.
struct BluetoothLogView: View {
    @State private var log = BLEEventLog.shared
    @State private var didCopy = false

    var body: some View {
        ScrollViewReader { proxy in
            List {
                if log.events.isEmpty {
                    ContentUnavailableView(
                        "No Bluetooth activity yet",
                        systemImage: "dot.radiowaves.left.and.right",
                        description: Text("Connect a device or send a stimulus and it will show up here.")
                    )
                    .listRowBackground(Color.clear)
                } else {
                    logSection
                }
                actionsSection
            }
            .navigationTitle("Bluetooth log")
            .navigationBarTitleDisplayMode(.inline)
            // Oldest first reads as a sequence (write, then its ack), so open
            // at the bottom where the thing you just did is.
            .onAppear {
                if let last = log.events.last { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: log.transcript) {
                    Image(systemName: "square.and.arrow.up")
                }
                .disabled(log.events.isEmpty)
                .accessibilityLabel("Share log")
            }
        }
        .accessibilityIdentifier("bluetoothLogScreen")
    }

    /// One card of monospaced lines. Each line is its own row (separators
    /// hidden) rather than one giant `Text`, so 500 lines stay lazy.
    private var logSection: some View {
        Section {
            ForEach(log.events) { event in
                (Text(event.time).foregroundStyle(.secondary)
                    + Text(" " + event.message).foregroundStyle(color(for: event)))
                    .font(.footnote.monospaced())
                    .textSelection(.enabled)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(
                        top: event.id == log.events.first?.id ? 12 : 2,
                        leading: 16,
                        bottom: event.id == log.events.last?.id ? 12 : 2,
                        trailing: 16
                    ))
                    .id(event.id)
            }
        }
    }

    private var actionsSection: some View {
        Section {
            Button(didCopy ? "Copied" : "Copy log") {
                UIPasteboard.general.string = log.transcript
                didCopy = true
            }
            .disabled(log.events.isEmpty)
            .accessibilityIdentifier("copyBluetoothLogButton")
            Button("Clear log", role: .destructive) {
                log.clear()
                didCopy = false
            }
            .disabled(log.events.isEmpty)
            .accessibilityIdentifier("clearBluetoothLogButton")
        } footer: {
            Text("The log keeps the last \(BLEEventLog.limit) lines from this launch only.")
        }
    }

    /// Errors in orange (a dropped link is the common case and isn't always a
    /// fault); a completed connection or acknowledged write in green, since
    /// those are the lines that answer "did it arrive?".
    private func color(for event: BLEEvent) -> Color {
        if event.level == .error { return .orange }
        if event.message.hasPrefix("Connected to") || event.message.hasPrefix("Write acknowledged") {
            return .accentColor
        }
        return .primary
    }
}
