import SwiftUI

// MARK: - Device hero card

struct DeviceHeroCard: View {
    let device: PavlokDevice?
    let connectionState: DeviceConnectionState
    /// Whether a wearable has ever been paired — decides between "pair one"
    /// and "we're working on getting yours back".
    let hasPairedDevice: Bool
    /// Known even while the device is unreachable.
    let pairedDeviceName: String?
    let onPairDevice: () -> Void
    let onTryAgain: () -> Void

    private var isConnected: Bool { connectionState == .connected }

    var body: some View {
        Group {
            if isConnected {
                connectedContent
            } else {
                disconnectedContent
            }
        }
        .remoteCard(isConnected ? .device : .neutral)
        .accessibilityIdentifier("deviceStatusRow")
    }

    private var connectedContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 7) {
                    statusBadge
                    Text(device?.name ?? "No device")
                        .font(.remoteNumeral(22))
                        .foregroundStyle(.white)
                    Text(device?.family.displayName ?? "Connected")
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

            HStack {
                Spacer()
                NavigationLink(value: RemoteDestination.deviceDetail) {
                    Text("More info ›").font(.footnote.weight(.medium))
                }
                .foregroundStyle(Color.accentColor)
            }
        }
    }

    /// Firing a stimulus is the *only* thing a missing device costs you —
    /// pokes to friends, alarms and settings all carry on — so this says so
    /// rather than reading as a dead end, and makes the way out the card's
    /// primary action. A device that *is* paired but unreachable gets named
    /// and gets "Try again" first: replacing it is rarely what you want.
    ///
    /// No `accessibilityIdentifier`s in here: the card-level `deviceStatusRow`
    /// identifier propagates down and overrides anything set on children, so
    /// one here would silently never match. Tests query by label instead.
    private var disconnectedContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            statusBadge
            Text(title)
                .font(.remoteNumeral(30))
                .foregroundStyle(.white)
                .padding(.top, 2)
            Text(disconnectedMessage)
                .font(.callout)
                .foregroundStyle(.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)

            Group {
                if link == .none {
                    heroButton("Pair a device", prominent: true, action: onPairDevice)
                } else {
                    HStack(spacing: 10) {
                        heroButton("Try again", prominent: true, action: onTryAgain)
                        heroButton("Pair a different device", prominent: false, action: onPairDevice)
                    }
                }
            }
            .padding(.top, 12)
        }
    }

    private func heroButton(_ title: String, prominent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)
                .foregroundStyle(prominent ? .black : .white)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(Capsule().fill(prominent ? Color.accentColor : .white.opacity(0.10)))
        }
        .buttonStyle(.plain)
    }

    private var statusBadge: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Circle().fill(statusTint).frame(width: 7, height: 7)
            Text(statusLabel)
                .font(.caption2.weight(.semibold))
                .tracking(1.2)
                .foregroundStyle(statusTint)
        }
    }

    /// The five things the card can be saying, collapsed from the connection
    /// state plus whether anything is paired.
    private enum Link: Equatable {
        case connected, none, offline, connecting, failed(String)
    }

    private var link: Link {
        switch connectionState {
        case .connected: return .connected
        case .connecting: return .connecting
        // A scan from the pair sheet isn't a reconnect attempt; with nothing
        // paired it's still "no device".
        case .scanning: return hasPairedDevice ? .connecting : .none
        case .disconnected: return hasPairedDevice ? .offline : .none
        case .failed(let reason): return .failed(reason)
        }
    }

    private var title: String {
        switch link {
        case .connected: return device?.name ?? "Connected"
        case .none: return "Not connected"
        case .offline, .connecting, .failed: return pairedDeviceName ?? "Not connected"
        }
    }

    private var disconnectedMessage: String {
        switch link {
        case .connected: return "Ready to fire."
        case .none: return "Alarms, friends and pokes still work. Firing needs a paired Pavlok."
        case .offline: return "Still paired. The app keeps trying to reconnect in the background."
        case .connecting: return "Keep the device close while it connects."
        case .failed: return "The connection didn't go through. Move closer, then try again."
        }
    }

    private var statusLabel: String {
        switch link {
        case .connected: return "CONNECTED"
        case .none: return "NO DEVICE"
        case .offline: return "NOT CONNECTED · Out of range or switched off"
        case .connecting: return "CONNECTING · Looking for your Pavlok"
        case .failed(let reason): return "FAILED · \(reason)"
        }
    }

    private var statusTint: Color {
        switch link {
        case .connected: return .accentColor
        case .none: return .white.opacity(0.5)
        case .offline: return .orange
        case .connecting: return .cyan
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
    let deviceName: String?
    let firingMode: FiringInteractionMode
    let onEdit: () -> Void
    let onFire: () -> Void
    /// A tap while `isEnabled` is false — explains that there's no device.
    let onUnavailable: () -> Void

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
                confirmTitle: "Fire \(kind.displayName)?",
                confirmMessage: "\(kind.displayName) at \(config.intensity)%\(deviceName.map { " on \($0)" } ?? "").",
                confirmActionTitle: "Fire",
                onUnavailable: onUnavailable,
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
                : "No device connected — pair one to fire")
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
                .accessibilityIdentifier("quickPokeComposerButton")
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
