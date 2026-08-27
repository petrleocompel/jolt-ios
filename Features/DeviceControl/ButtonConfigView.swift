import SwiftUI

struct ButtonConfigView: View {
    let viewModel: DeviceControlViewModel
    @State private var configs: [ButtonPressType: ButtonAction] = [
        .singlePress: .fireStimulus,
        .doublePress: .snoozeActiveAlarm,
        .longPress: .toggleMute
    ]
    @State private var errorMessage: String?

    var body: some View {
        List {
            ForEach(ButtonPressType.allCases, id: \.self) { press in
                Section(press.displayName) {
                    Picker("Action", selection: bindingFor(press)) {
                        ForEach(ButtonAction.allCases) { action in
                            Text(action.displayName).tag(action)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
            }
        }
        .navigationTitle("Button")
        .alert("Couldn't save", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func bindingFor(_ press: ButtonPressType) -> Binding<ButtonAction> {
        Binding(
            get: { configs[press] ?? .none },
            set: { newValue in
                configs[press] = newValue
                save(press: press, action: newValue)
            }
        )
    }

    private func save(press: ButtonPressType, action: ButtonAction) {
        Task {
            do {
                try await viewModel.setButtonConfig(ButtonConfig(pressType: press, action: action, stimulus: nil), press: press)
            } catch {
                errorMessage = "\(error)"
            }
        }
    }
}

private extension ButtonPressType {
    var displayName: String {
        switch self {
        case .singlePress: return "Single press"
        case .doublePress: return "Double press"
        case .longPress: return "Long press"
        }
    }
}
