import SwiftUI

// MARK: - Device hero card

struct DeviceHeroCard: View {
    let device: PavlokDevice?
    let connectionState: DeviceConnectionState

    private var isConnected: Bool { connectionState == .connected }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 7) {
                        Circle().fill(statusTint).frame(width: 7, height: 7)
                        Text(statusLabel)
                            .font(.caption2.weight(.semibold))
                            .tracking(1.2)
                            .foregroundStyle(statusTint)
                    }
                    Text(device?.name ?? "No device")
                        .font(.remoteNumeral(22))
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.5))
                }
                Spacer(minLength: 8)
                if let battery = device?.info.batteryLevelPercent {
                    batteryReadout(battery)
                }
            }

            if let battery = device?.info.batteryLevelPercent {
                batteryBar(percent: battery)
            }

            if isConnected {
                HStack {
                    Spacer()
                    NavigationLink(value: RemoteDestination.deviceDetail) {
                        Text("More info ›").font(.footnote.weight(.medium))
                    }
                    .foregroundStyle(Color.accentColor)
                }
            } else {
                Label {
                    Text("Connect your Pavlok to send a stimulus.")
                        .foregroundStyle(.white.opacity(0.75))
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
                .font(.subheadline)
                .accessibilityIdentifier("disconnectedNotice")
            }
        }
        .remoteCard(isConnected ? .device : .neutral)
        .accessibilityIdentifier("deviceStatusRow")
    }

    private var statusLabel: String {
        switch connectionState {
        case .connected: return "CONNECTED"
        case .connecting: return "CONNECTING"
        case .scanning: return "SCANNING"
        case .disconnected: return "NOT CONNECTED"
        case .failed: return "FAILED"
        }
    }

    private var subtitle: String {
        switch connectionState {
        case .connected: return device?.family.displayName ?? "Connected"
        case .connecting: return "Connecting…"
        case .scanning: return "Scanning…"
        case .disconnected: return "Nothing can fire until you connect"
        case .failed(let reason): return reason
        }
    }

    private var statusTint: Color {
        switch connectionState {
        case .connected, .connecting, .scanning: return .accentColor
        case .disconnected: return .white.opacity(0.5)
        case .failed: return .red
        }
    }

    private func batteryReadout(_ percent: Int) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            HStack(alignment: .top, spacing: 2) {
                Text("\(percent)").font(.remoteNumeral(50)).foregroundStyle(.white)
                Text("%")
                    .font(.remoteNumeral(16, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.top, 6)
            }
            Text("BATTERY")
                .font(.caption2.weight(.semibold))
                .tracking(0.6)
                .foregroundStyle(.white.opacity(0.42))
        }
    }

    private func batteryBar(percent: Int) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.12))
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: geometry.size.width * max(0, min(1, Double(percent) / 100)))
            }
        }
        .frame(height: 3)
    }
}

// MARK: - Stimulus row

struct StimulusRow: View {
    let kind: StimulusKind
    let config: StimulusConfig
    let isEnabled: Bool
    let firingMode: FiringInteractionMode
    let onEdit: () -> Void
    let onFire: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Button(action: onEdit) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Image(systemName: kind.symbolName).foregroundStyle(.white.opacity(0.85))
                        Text(kind.displayName)
                            .font(.remoteNumeral(17))
                            .foregroundStyle(.white)
                        if config.intensity > FireControl<AnyView>.defaultHighIntensityThreshold {
                            Text("HIGH")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(RemoteTheme.amber)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5)
                                        .strokeBorder(RemoteTheme.amber.opacity(0.42))
                                )
                        }
                    }
                    HStack(alignment: .lastTextBaseline, spacing: 3) {
                        Text("\(config.intensity)").font(.remoteNumeral(36)).foregroundStyle(.white)
                        Text("%").font(.footnote).foregroundStyle(.white.opacity(0.45))
                        Text(config.repetitions > 1 ? "×\(config.repetitions)" : "\(firingMode.actionVerb.lowercased()) to fire")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.42))
                            .padding(.leading, 4)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("stimulusCard_\(kind.rawValue)")
            .accessibilityElement(children: .combine)
            .accessibilityHint("Opens intensity and repetitions settings")

            Spacer(minLength: 0)

            FireControl(
                mode: firingMode,
                isEnabled: isEnabled,
                confirmTitle: "Send \(kind.displayName) at \(config.intensity)%?",
                highIntensityPercent: config.intensity,
                onFire: onFire,
                label: { state in
                    StimulusFireRing(kind: kind, state: state)
                }
            )
            .accessibilityIdentifier("fireButton_\(kind.rawValue)")
            .accessibilityLabel("\(kind.displayName), \(config.intensity) percent")
            .accessibilityHint(isEnabled
                ? "Fires a \(kind.displayName.lowercased())"
                : "Unavailable while no device is connected")
        }
        .remoteCard(.stimulus)
    }
}

struct StimulusFireRing: View {
    let kind: StimulusKind
    let state: FireControlState

    var body: some View {
        ZStack {
            Circle().fill(Color.accentColor.opacity(state.isHolding ? 0.18 : 0.10))
            Circle().strokeBorder(Color.accentColor.opacity(state.isHolding ? 0.5 : 0.35), lineWidth: 1)
            Circle()
                .trim(from: 0, to: state.progress)
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: kind.symbolName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.accentColor)
        }
        .frame(width: 64, height: 64)
    }
}

// MARK: - Quick poke card

struct QuickPokeCard: View {
    let settings: QuickPokeSettings
    let firingMode: FiringInteractionMode
    let lastError: String?
    let feedback: PokeFeedbackService
    let onFire: () -> Void
    let onOpenComposer: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(RemoteTheme.violet.opacity(0.22))
                        Circle().strokeBorder(RemoteTheme.violet.opacity(0.45))
                        Text(initials).font(.remoteNumeral(16)).foregroundStyle(RemoteTheme.violetInk)
                    }
                    .frame(width: 46, height: 46)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("QUICK POKE")
                            .font(.caption2.weight(.semibold))
                            .tracking(1.2)
                            .foregroundStyle(RemoteTheme.violet)
                        Text(settings.targetFriendName ?? "Friend")
                            .font(.remoteNumeral(19))
                            .foregroundStyle(.white)
                    }
                }
                Spacer(minLength: 8)
                Button(action: onOpenComposer) {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(.white.opacity(0.5))
                }
                .accessibilityLabel("Adjust and send a one-off poke")
            }

            HStack(spacing: 8) {
                chip("\(settings.stimulus.kind.displayName) · \(settings.stimulus.intensity)%")
                if settings.stimulus.repetitions > 1 {
                    chip("×\(settings.stimulus.repetitions)")
                }
                if let lastError {
                    Text(lastError).font(.caption).foregroundStyle(.red)
                }
            }

            FireControl(
                mode: firingMode,
                confirmTitle: "Poke \(settings.targetFriendName ?? "friend")?",
                onFire: onFire,
                label: { state in
                    HoldFillBar(
                        isHolding: state.isHolding,
                        progress: state.progress,
                        idleLabel: "\(firingMode.actionVerb) to poke \(settings.targetFriendName ?? "friend")",
                        holdingLabel: "Keep holding…",
                        tint: RemoteTheme.violet,
                        ink: .white,
                        isShowingSuccess: feedback.isShowingSuccessLabel,
                        isFlashing: feedback.isFlashing
                    )
                }
            )
            .accessibilityIdentifier("quickPokeButton")
        }
        .remoteCard(.quickPoke)
    }

    private var initials: String {
        let parts = (settings.targetFriendName ?? "?").split(separator: " ")
        let letters = parts.prefix(2).compactMap(\.first)
        return String(letters).uppercased()
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.white.opacity(0.75))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.16)))
    }
}

// MARK: - Next alarm card

struct NextAlarmCard: View {
    let alarm: Alarm
    let occursAt: Date
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                Text("NEXT ALARM")
                    .font(.caption2.weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.45))
                HStack(alignment: .lastTextBaseline, spacing: 8) {
                    Text(timeString).font(.remoteNumeral(32)).foregroundStyle(.white)
                    Text(relativeString).font(.footnote).foregroundStyle(.white.opacity(0.45))
                }
                Text(summary).font(.footnote).foregroundStyle(.white.opacity(0.6))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .remoteCard(.neutral)
    }

    private var timeString: String { String(format: "%02d:%02d", alarm.hour, alarm.minute) }

    private var relativeString: String {
        let interval = max(0, occursAt.timeIntervalSinceNow)
        let hours = Int(interval / 3600)
        let minutes = Int((interval.truncatingRemainder(dividingBy: 3600)) / 60)
        return "in \(hours)h \(minutes)m"
    }

    private var summary: String {
        var text = "\(alarm.stimulus.kind.displayName) \(alarm.stimulus.intensity)%"
        if alarm.dismissChallenge != .none {
            text += " · \(alarm.dismissChallenge.displayName)"
        }
        return text
    }
}

// MARK: - Recent activity card

struct RecentActivityCard: View {
    let events: [PokeEvent]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("RECENT ACTIVITY")
                .font(.caption2.weight(.semibold))
                .tracking(1.2)
                .foregroundStyle(.white.opacity(0.45))
            ForEach(events) { event in
                HStack(spacing: 11) {
                    Text(title(for: event))
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.82))
                    Spacer(minLength: 8)
                    Text(event.createdAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.38))
                }
            }
        }
        .remoteCard(.neutral)
    }

    private func title(for event: PokeEvent) -> String {
        switch event.direction {
        case .sent: return "You \(event.stimulus.kind.pastTenseVerb) \(event.friendDisplayName)"
        case .received: return "\(event.friendDisplayName) \(event.stimulus.kind.pastTenseVerb) you"
        }
    }
}
