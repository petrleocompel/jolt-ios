import SwiftUI

/// One row per real `DeviceButtonSlot` — see its doc comment for why this
/// isn't a (button, pressType) grid.
///
/// The screen loads the device's *actual* configuration on appear rather than
/// starting blank. That matters more than it sounds: without it every picker
/// read "Device default" whatever the device thought, so there was no way to
/// tell a button that had been set from one that hadn't, and no way to tell a
/// rejected write from an applied one. `ButtonConfigReport` explains why this
/// is a write-then-listen exchange and not a GATT read.
///
/// Setting a button to "Find my phone" is also how you make a press reach the
/// phone at all — see `PokeTriggerService.makeButtonReportPresses()`.
struct ButtonConfigView: View {
    let viewModel: DeviceControlViewModel
    @State private var actions: [DeviceButtonSlot: ButtonAction] = [:]
    @State private var errorMessage: String?
    @State private var report: ButtonConfigReport?
    @State private var isLoading = false
    /// Guards against the load writing back what it just read. Picker
    /// bindings fire on *any* change, including the programmatic one that
    /// applying a report causes, so without this a refresh would write all
    /// six buttons back to the device.
    @State private var isApplyingReport = false

    var body: some View {
        List {
            if isLoading && report == nil {
                Section { Label("Reading configuration…", systemImage: "arrow.clockwise") }
            }
            ForEach(DeviceButtonSlot.configurableCases) { slot in
                Section(slot.displayName) {
                    Picker("Action", selection: bindingFor(slot)) {
                        ForEach(ButtonAction.allCases) { action in
                            Text(action.displayName).tag(action)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    if let record = report?.records[slot] {
                        LabeledContent("On device") {
                            Text(record.hexString).font(.footnote.monospaced())
                        }
                    }
                }
            }
            diagnosticsSection
        }
        .navigationTitle("Button")
        .toolbar {
            Button("Refresh", systemImage: "arrow.clockwise") { Task { await load() } }
                .disabled(isLoading)
                .accessibilityIdentifier("buttonConfigRefresh")
        }
        .task { await load() }
        .errorBanner(errorMessage) { errorMessage = nil }
    }

    private var diagnosticsSection: some View {
        Section {
            if let report, !report.frames.isEmpty {
                LabeledContent("Frames") {
                    Text(report.frames.map { frame in
                        frame.map { String(format: "%02X", $0) }.joined()
                    }.joined(separator: " · "))
                        .font(.footnote.monospaced())
                }
            }
            if let report, report.frames.isEmpty, !isLoading {
                Text("The device sent nothing back. Either it is not connected or this "
                    + "firmware answers the config query differently.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Raw report")
        } footer: {
            Text("Writable actions are the ones whose payload length is recovered — the device "
                + "rejects a payload of the wrong length outright. \"Zap\", \"Beep\" and "
                + "\"Vibrate\" are listed but not written, because a wrong guess at their "
                + "intensity bytes fires a real stimulus on your wrist. "
                + "See docs/RE-FINDINGS.md.")
                .font(.footnote)
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let fresh = try await viewModel.readButtonConfig()
            isApplyingReport = true
            report = fresh
            actions = fresh.actions
            isApplyingReport = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func bindingFor(_ slot: DeviceButtonSlot) -> Binding<ButtonAction> {
        Binding(
            get: { actions[slot] ?? .defaultAction },
            set: { newValue in
                guard !isApplyingReport, actions[slot] != newValue else { return }
                actions[slot] = newValue
                save(slot: slot, action: newValue)
            }
        )
    }

    private func save(slot: DeviceButtonSlot, action: ButtonAction) {
        Task {
            do {
                try await viewModel.setButtonConfig(ButtonConfig(slot: slot, action: action))
                // Read back rather than trust the acknowledgement: the write
                // being accepted and the button actually holding the new
                // action are different claims, and only the second is worth
                // showing the user.
                await load()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
