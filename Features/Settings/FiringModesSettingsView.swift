import SwiftUI

/// Per-stimulus firing mode pickers — Zap can confirm while Vibe stays tap.
struct FiringModesSettingsView: View {
    @Bindable var service: FiringModeService

    var body: some View {
        List {
            ForEach(StimulusKind.allCases) { kind in
                Picker(kind.displayName, selection: Binding(
                    get: { service.mode(for: kind) },
                    set: { service.setMode($0, for: kind) }
                )) {
                    ForEach(FiringInteractionMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .accessibilityIdentifier("firingModePicker_\(kind.rawValue)")
            }
        }
        .navigationTitle("Firing")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("firingModesSettingsScreen")
    }
}
