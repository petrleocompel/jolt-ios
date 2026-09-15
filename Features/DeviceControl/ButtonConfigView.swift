import SwiftUI

/// One row per real `DeviceButtonSlot` — see its doc comment for why this
/// isn't a (button, pressType) grid. Only the actions whose payload is
/// recovered can be saved; picking any other surfaces why rather than
/// pretending to work.
///
/// Setting a button to "Find my phone" is also how you make a press reach the
/// phone at all — see `PokeTriggerService.makeButtonReportPresses()`.
struct ButtonConfigView: View {
    let viewModel: DeviceControlViewModel
    @State private var actions: [DeviceButtonSlot: ButtonAction] = [:]
    @State private var errorMessage: String?
    @State private var readback: String?

    var body: some View {
        List {
            ForEach(DeviceButtonSlot.allCases) { slot in
                Section(slot.displayName) {
                    Picker("Action", selection: bindingFor(slot)) {
                        ForEach(ButtonAction.allCases) { action in
                            Text(action.displayName).tag(action)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
            }
            Section {
                Button("Read setup characteristic") {
                    Task {
                        do {
                            let bytes = try await viewModel.readRawButtonConfig()
                            readback = bytes.isEmpty
                                ? "(empty)"
                                : bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                }
                if let readback {
                    LabeledContent("Raw read") {
                        Text(readback).font(.footnote.monospaced())
                    }
                }
            } footer: {
                Text("Writable actions are the ones whose payload length is recovered — the device "
                    + "rejects a payload of the wrong length outright. The rest are listed for "
                    + "reference; picking one says so rather than guessing bytes that could fire a "
                    + "stimulus. The raw read is not the config: a plain read of the setup "
                    + "characteristic returns one status byte, not the stored actions. "
                    + "See docs/RE-FINDINGS.md.")
                    .font(.footnote)
            }
        }
        .navigationTitle("Button")
        .errorBanner(errorMessage) { errorMessage = nil }
    }

    private func bindingFor(_ slot: DeviceButtonSlot) -> Binding<ButtonAction> {
        Binding(
            get: { actions[slot] ?? .defaultAction },
            set: { newValue in
                actions[slot] = newValue
                save(slot: slot, action: newValue)
            }
        )
    }

    private func save(slot: DeviceButtonSlot, action: ButtonAction) {
        Task {
            do {
                try await viewModel.setButtonConfig(ButtonConfig(slot: slot, action: action))
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
