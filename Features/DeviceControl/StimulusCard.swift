import SwiftUI

/// Editing intensity/repetitions for one stimulus kind, presented as a sheet
/// from the Remote dashboard's stimulus row (tapping its label, as opposed to
/// its hold-to-fire control). Firing lives on the dashboard row itself now —
/// this is purely "change and save the default", which is why it has no send
/// button of its own.
struct StimulusIntensityEditorSheet: View {
    let kind: StimulusKind
    let onSave: (StimulusConfig) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var intensity: Double
    @State private var repetitions: Int

    init(kind: StimulusKind, config: StimulusConfig, onSave: @escaping (StimulusConfig) -> Void) {
        self.kind = kind
        self.onSave = onSave
        _intensity = State(initialValue: Double(config.intensity))
        _repetitions = State(initialValue: config.repetitions)
    }

    private var edited: StimulusConfig {
        StimulusConfig(kind: kind, intensity: Int(intensity), repetitions: repetitions)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Intensity")
                            Spacer()
                            Text("\(Int(intensity))%")
                                .font(.subheadline.weight(.semibold))
                                .monospacedDigit()
                        }
                        let bounds = StimulusConfig.intensityRange
                        Slider(
                            value: $intensity,
                            in: Double(bounds.lowerBound)...Double(bounds.upperBound),
                            step: 1
                        )
                        .tint(kind.tint)
                        .accessibilityIdentifier("intensitySlider_\(kind.rawValue)")
                        .accessibilityLabel("\(kind.displayName) intensity")
                        .accessibilityValue("\(Int(intensity)) percent")
                    }

                    Stepper(value: $repetitions, in: 1...5) {
                        HStack {
                            Text("Repetitions")
                            Spacer()
                            Text("\(repetitions)×")
                                .font(.subheadline.weight(.semibold))
                                .monospacedDigit()
                        }
                    }
                    .accessibilityIdentifier("repetitionsStepper_\(kind.rawValue)")
                }
            }
            .navigationTitle("\(kind.displayName) settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(edited)
                        dismiss()
                    }
                    .accessibilityIdentifier("saveStimulusButton_\(kind.rawValue)")
                }
            }
        }
    }
}

extension StimulusKind {
    var symbolName: String {
        switch self {
        case .zap: return "bolt.fill"
        case .vibe: return "waveform"
        case .beep: return "speaker.wave.2.fill"
        }
    }

    /// Zap is the one that hurts, so it gets the warning colour; the other
    /// two are visually calmer on purpose.
    var tint: Color {
        switch self {
        case .zap: return .orange
        case .vibe: return .indigo
        case .beep: return .teal
        }
    }
}
