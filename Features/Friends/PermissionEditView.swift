import SwiftUI

struct PermissionEditView: View {
    let friendID: Friend.ID
    let viewModel: FriendsViewModel

    /// Hoisted here, rather than one `@FocusState` per `EditableSliderRow`:
    /// a `.toolbar(placement: .keyboard)` attached inside a `Form` row
    /// doesn't reliably dock above the keyboard — it renders in place, on
    /// top of the row itself. A single toolbar owned by the `Form` avoids
    /// that; rows just report which field (if any) is theirs.
    @FocusState private var focusedField: String?

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
                    Section {
                        Toggle("Allow", isOn: allowedBinding(friend: friend, kind: kind, permission: permission))
                        if permission.isAllowed {
                            EditableSliderRow(
                                label: "Max intensity",
                                value: maxIntensityBinding(friend: friend, kind: kind, permission: permission),
                                range: 0...StimulusConfig.intensityRange.upperBound,
                                unit: "%",
                                tint: kind.tint,
                                accessibilityID: "\(kind.rawValue)Intensity",
                                focusedField: $focusedField
                            )
                            EditableSliderRow(
                                label: "Cooldown",
                                value: cooldownBinding(friend: friend, kind: kind, permission: permission),
                                range: 0...600,
                                unit: "s",
                                tint: kind.tint,
                                accessibilityID: "\(kind.rawValue)Cooldown",
                                focusedField: $focusedField
                            )
                        }
                    } header: {
                        Label(kind.displayName, systemImage: kind.symbolName)
                            .foregroundStyle(kind.tint)
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

    /// Grant only: a preset says nothing about automated pokes, so whatever
    /// was answered there can't stop it from reading as active.
    func matches(_ set: FriendPermissionSet) -> Bool {
        StimulusKind.allCases.allSatisfy { set[$0].hasSameGrant(as: value) }
    }

    static let full = PermissionPreset(
        name: "Full",
        symbolName: "shield.fill",
        subtitle: "Allow everything, 100% intensity, no cooldown",
        value: .allowed(maxIntensity: 100, cooldownSeconds: 0)
    )

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

    static let all = [full, trusted, cautious, off]
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

/// A slider paired with a live number that becomes an editable text field on
/// tap — the poke composer's slider for at-a-glance dialing, plus exact entry
/// for anyone who wants a precise value. Drags update a local copy only;
/// `value` (and the network write it triggers) is committed once on release
/// so dragging doesn't fire a request per pixel.
private struct EditableSliderRow: View {
    let label: String
    let value: Binding<Int>
    let range: ClosedRange<Int>
    let unit: String
    let tint: Color
    let accessibilityID: String
    var focusedField: FocusState<String?>.Binding

    @State private var liveValue: Double = 0
    @State private var isEditingText = false
    @State private var textValue = ""

    private var isFocused: Bool { focusedField.wrappedValue == accessibilityID }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(label.uppercased())
                    .font(.caption2.weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(.secondary)
                Spacer()
                numberField
            }
            Slider(
                value: $liveValue,
                in: Double(range.lowerBound)...Double(range.upperBound),
                onEditingChanged: { editing in
                    if !editing { commit(Int(liveValue.rounded())) }
                }
            )
            .tint(tint)
            .accessibilityIdentifier("\(accessibilityID)Slider")
        }
        .onAppear { liveValue = Double(value.wrappedValue) }
        .onChange(of: value.wrappedValue) { _, newValue in
            if !isEditingText { liveValue = Double(newValue) }
        }
        .onChange(of: isFocused) { _, focused in
            if !focused && isEditingText { commitText() }
        }
    }

    @ViewBuilder
    private var numberField: some View {
        if isEditingText {
            // No keyboard toolbar here on purpose: `.toolbar(placement:
            // .keyboard)` attached this deep inside a Form/List doesn't
            // reliably dock above the keyboard — it renders in place, on
            // top of whichever row happens to be focused. An inline commit
            // button next to the field sidesteps that entirely.
            HStack(spacing: 6) {
                TextField("", text: $textValue)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 44)
                    .focused(focusedField, equals: accessibilityID)
                    .accessibilityIdentifier("\(accessibilityID)ValueField")
                Text(unit).font(.footnote).foregroundStyle(.secondary)
                Button {
                    commitText()
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                }
                .accessibilityIdentifier("\(accessibilityID)ValueFieldCommit")
            }
        } else {
            Button {
                // Blank, not pre-filled with the current value: SwiftUI's
                // `TextField` doesn't select-all on focus, so pre-filling
                // would mean typing appends instead of replaces (e.g. "0"
                // + "75" reads as "075" mid-edit).
                textValue = ""
                isEditingText = true
                focusedField.wrappedValue = accessibilityID
            } label: {
                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    Text("\(Int(liveValue))").font(.title3.weight(.semibold).monospacedDigit())
                    Text(unit).font(.footnote).foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("\(accessibilityID)ValueButton")
        }
    }

    private func commitText() {
        if let parsed = Int(textValue) {
            let clamped = min(max(parsed, range.lowerBound), range.upperBound)
            liveValue = Double(clamped)
            commit(clamped)
        } else {
            liveValue = Double(value.wrappedValue)
        }
        isEditingText = false
        if isFocused { focusedField.wrappedValue = nil }
    }

    private func commit(_ newValue: Int) {
        if newValue != value.wrappedValue {
            value.wrappedValue = newValue
        }
    }
}
