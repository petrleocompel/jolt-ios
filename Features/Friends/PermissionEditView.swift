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
