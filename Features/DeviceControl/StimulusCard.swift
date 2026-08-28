import SwiftUI

/// One stimulus kind: its own intensity, its own repetition count, its own
/// send button.
///
/// The intensity lives on the card rather than in a single shared slider at
/// the top of the screen. A comfortable vibe and a tolerable zap are
/// different numbers, so a shared slider means re-adjusting before every
/// switch — and worse, means a value dialled in for a vibe can be sent as a
/// zap by accident.
struct StimulusCard: View {
    let kind: StimulusKind
    let isEnabled: Bool
    /// Current saved value; the card seeds its editing state from this.
    let config: StimulusConfig
    let onSend: (StimulusConfig) -> Void
    let onSave: (StimulusConfig) -> Void

    @State private var intensity: Double
    @State private var repetitions: Int
    @State private var isExpanded = false

    init(
        kind: StimulusKind,
        isEnabled: Bool,
        config: StimulusConfig,
        onSend: @escaping (StimulusConfig) -> Void,
        onSave: @escaping (StimulusConfig) -> Void
    ) {
        self.kind = kind
        self.isEnabled = isEnabled
        self.config = config
        self.onSend = onSend
        self.onSave = onSave
        _intensity = State(initialValue: Double(config.intensity))
        _repetitions = State(initialValue: config.repetitions)
    }

    private var edited: StimulusConfig {
        StimulusConfig(kind: kind, intensity: Int(intensity), repetitions: repetitions)
    }

    private var hasUnsavedChanges: Bool {
        edited != config
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if isExpanded {
                editor
            }
            sendButton
        }
        .padding(16)
        // `secondarySystemGroupedBackground` over the grouped list background
        // is exactly what a native inset-grouped row uses, so these cards sit
        // at the same elevation as every other row in the app in both light
        // and dark mode.
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityIdentifier("stimulusCard_\(kind.rawValue)")
        // Re-seed the editors when the saved value changes underneath us
        // (another screen, a device sync). Doing this with `.id()` on the
        // card instead would rebuild the whole view and collapse it every
        // time the user pressed Save.
        .onChange(of: config) { _, new in
            intensity = Double(new.intensity)
            repetitions = new.repetitions
        }
    }

    private var header: some View {
        Button {
            withAnimation(.snappy) { isExpanded.toggle() }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: kind.symbolName)
                    .font(.title3)
                    .foregroundStyle(kind.tint)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.displayName)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Spacer()

                Image(systemName: "chevron.down")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isExpanded ? 0 : -90))
            }
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("stimulusCardHeader_\(kind.rawValue)")
        .accessibilityLabel("\(kind.displayName) settings, \(summary)")
        .accessibilityHint(isExpanded ? "Collapses intensity controls" : "Expands intensity controls")
    }

    private var summary: String {
        repetitions == 1
            ? "\(config.intensity)%"
            : "\(config.intensity)% · \(repetitions)×"
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 12) {
            let bounds = StimulusConfig.intensityRange
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Intensity")
                        .font(.subheadline)
                    Spacer()
                    Text("\(Int(intensity))%")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                }
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
                        .font(.subheadline)
                    Spacer()
                    Text("\(repetitions)×")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                }
            }
            .accessibilityIdentifier("repetitionsStepper_\(kind.rawValue)")

            Button {
                onSave(edited)
            } label: {
                Label("Save as default", systemImage: "square.and.arrow.down")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
            }
            .buttonStyle(.bordered)
            .disabled(!hasUnsavedChanges)
            .accessibilityIdentifier("saveStimulusButton_\(kind.rawValue)")
            .accessibilityHint("Stores this intensity on the phone and, when connected, on the device")
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var sendButton: some View {
        Button {
            onSend(edited)
        } label: {
            Text("Send \(kind.displayName.lowercased())")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
        }
        .buttonStyle(.borderedProminent)
        .tint(kind.tint)
        .disabled(!isEnabled)
        .accessibilityIdentifier("fireButton_\(kind.rawValue)")
        .accessibilityHint(isEnabled
            ? "Sends a \(kind.displayName.lowercased()) at \(Int(intensity)) percent"
            : "Unavailable while no device is connected")
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
