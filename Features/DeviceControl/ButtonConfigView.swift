import SwiftUI

/// One row per real `DeviceButtonSlot` — see its doc comment for why this
/// isn't a (button, pressType) grid. Only "Off" can actually be saved right
/// now; picking anything else surfaces why rather than pretending to work.
struct ButtonConfigView: View {
    let viewModel: DeviceControlViewModel
    @State private var actions: [DeviceButtonSlot: ButtonAction] = [:]
    @State private var errorMessage: String?

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
                Text("Only \"Off\" is confirmed to work against real hardware today. "
                    + "Other actions are shown for reference but aren't wired up yet — see docs/RE-FINDINGS.md.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
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
