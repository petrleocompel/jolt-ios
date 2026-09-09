import SwiftUI

struct PermissionEditView: View {
    let friendID: Friend.ID
    let viewModel: FriendsViewModel

    private var friend: Friend? {
        viewModel.friends.first(where: { $0.id == friendID })
    }

    var body: some View {
        Form {
            if let friend {
                Section {
                    ForEach(PermissionPreset.all) { preset in
                        Button {
                            apply(preset, to: friend)
                        } label: {
                            PresetRow(preset: preset, isActive: preset.matches(friend.permissionsIGranted))
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Quick setup")
                } footer: {
                    Text("Applies to all three stimuli at once. Fine-tune any of them below.")
                }

                ForEach(StimulusKind.allCases) { kind in
                    let permission = friend.permissionsIGranted[kind]
                    Section(kind.displayName) {
                        Toggle("Allow", isOn: allowedBinding(friend: friend, kind: kind, permission: permission))
                        if permission.isAllowed {
                            Stepper(
                                "Max intensity: \(permission.maxIntensity)",
                                value: maxIntensityBinding(friend: friend, kind: kind, permission: permission),
                                in: 0...StimulusConfig.intensityRange.upperBound,
                                step: 5
                            )
                            Stepper(
                                "Cooldown: \(permission.cooldownSeconds)s",
                                value: cooldownBinding(friend: friend, kind: kind, permission: permission),
                                in: 0...600,
                                step: 10
                            )
                        }
                    }
                }
            }
        }
        .navigationTitle("Permissions")
        .errorBanner(viewModel.lastError) { viewModel.lastError = nil }
    }

    private func apply(_ preset: PermissionPreset, to friend: Friend) {
        for kind in StimulusKind.allCases {
            viewModel.updatePermission(for: friend, kind: kind, permission: preset.value)
        }
    }

    private func allowedBinding(friend: Friend, kind: StimulusKind, permission: StimulusPermission) -> Binding<Bool> {
        Binding(
            get: { permission.isAllowed },
            set: { newValue in
                var updated = permission
                updated.isAllowed = newValue
                viewModel.updatePermission(for: friend, kind: kind, permission: updated)
            }
        )
    }

    private func maxIntensityBinding(friend: Friend, kind: StimulusKind, permission: StimulusPermission) -> Binding<Int> {
        Binding(
            get: { permission.maxIntensity },
            set: { newValue in
                var updated = permission
                updated.maxIntensity = newValue
                viewModel.updatePermission(for: friend, kind: kind, permission: updated)
            }
        )
    }

    private func cooldownBinding(friend: Friend, kind: StimulusKind, permission: StimulusPermission) -> Binding<Int> {
        Binding(
            get: { permission.cooldownSeconds },
            set: { newValue in
                var updated = permission
                updated.cooldownSeconds = newValue
                viewModel.updatePermission(for: friend, kind: kind, permission: updated)
            }
        )
    }
}

/// A one-tap trust level applied identically across all three stimulus
/// kinds. Doesn't replace the per-kind controls below — just seeds them.
private struct PermissionPreset: Identifiable {
    let name: String
    let symbolName: String
    let subtitle: String
    let value: StimulusPermission

    var id: String { name }

    func matches(_ set: FriendPermissionSet) -> Bool {
        StimulusKind.allCases.allSatisfy { set[$0] == value }
    }

    static let trusted = PermissionPreset(
        name: "Trusted",
        symbolName: "checkmark.shield.fill",
        subtitle: "Allow everything, up to 60%, 15s cooldown",
        value: .allowed(maxIntensity: 60, cooldownSeconds: 15)
    )

    static let cautious = PermissionPreset(
        name: "Cautious",
        symbolName: "shield.lefthalf.filled",
        subtitle: "Allow everything, up to 20%, 2 min cooldown",
        value: .allowed(maxIntensity: 20, cooldownSeconds: 120)
    )

    static let off = PermissionPreset(
        name: "Off",
        symbolName: "shield.slash",
        subtitle: "Don't allow any stimulus from this friend",
        value: .disabled
    )

    static let all = [trusted, cautious, off]
}

private struct PresetRow: View {
    let preset: PermissionPreset
    let isActive: Bool

    var body: some View {
        HStack {
            Image(systemName: preset.symbolName)
                .foregroundStyle(isActive ? Color.accentColor : .secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(preset.name).foregroundStyle(.primary)
                Text(preset.subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if isActive {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
            }
        }
    }
}
