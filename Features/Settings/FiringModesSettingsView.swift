import SwiftUI

/// Per-stimulus firing mode pickers — Zap can confirm while Vibe stays tap.
struct FiringModesSettingsView: View {
    @Bindable var service: FiringModeService

    var body: some View {
        List {
            Section {
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
            } footer: {
                // Kept in step with `FireControl`: its hold duration and its
                // high-intensity threshold are what this describes.
                Text("Tap fires straight away. Hold needs a press of just under a second on the Remote button. "
                    + "Confirm asks first. In Hold mode, anything above "
                    + "\(FireControl<EmptyView>.defaultHighIntensityThreshold)% asks for a second hold.")
            }
        }
        .navigationTitle("Firing")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("firingModesSettingsScreen")
    }
}
