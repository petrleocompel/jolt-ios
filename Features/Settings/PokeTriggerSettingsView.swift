import SwiftUI

/// Configures the "poke a friend from your Pavlok" trigger (Approach A).
///
/// Flow: pick a friend, pick which button press sends the poke, and — because
/// a button set to a device-local action may never be announced over BLE —
/// let the app set that button to report presses. "Learn a gesture" remains
/// for anything the decoder doesn't recognise.
struct PokeTriggerSettingsView: View {
    @State var service: PokeTriggerService
    let friendsRepository: FriendsRepository

    @State private var friends: [Friend] = []

    private var trigger: PokeTrigger { service.trigger }

    var body: some View {
        List {
            enableSection
            if trigger.isEnabled {
                friendSection
                stimulusSection
                PokeTriggerPressSection(service: service)
                PokeTriggerEventsSection(service: service)
                statusSection
            }
        }
        .navigationTitle("Poke from Pavlok")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            for await list in friendsRepository.friends {
                friends = list
            }
        }
        .onDisappear { service.cancelLearning() }
        .accessibilityIdentifier("pokeTriggerSettingsScreen")
    }

    // MARK: Sections

    private var enableSection: some View {
        Section {
            Toggle("Poke a friend from your Pavlok", isOn: Binding(
                get: { service.trigger.isEnabled },
                set: { service.setEnabled($0) }
            ))
            .accessibilityIdentifier("pokeTriggerEnableToggle")
        } footer: {
            Text("The wearable already tells the phone when you press its button. "
                + "This turns a press you choose into an outgoing poke.")
        }
    }

    private var friendSection: some View {
        Section("Who to poke") {
            if friends.isEmpty {
                Text("Add a friend first — pokes go to someone on your friends list.")
                    .foregroundStyle(.secondary)
            } else {
                Picker("Friend", selection: Binding(
                    get: { service.trigger.targetFriendID },
                    set: { id in
                        guard let id else {
                            service.clearTarget()
                            return
                        }
                        if let friend = friends.first(where: { $0.id == id }) {
                            service.setTarget(friendID: id, name: friend.displayName)
                        }
                    }
                )) {
                    Text("None").tag(Friend.ID?.none)
                    ForEach(friends) { friend in
                        Text(friend.displayName).tag(Optional(friend.id))
                    }
                }
                .accessibilityIdentifier("pokeTriggerFriendPicker")
            }
        }
    }

    private var stimulusSection: some View {
        Section {
            Picker("Stimulus", selection: Binding(
                get: { service.trigger.stimulus.kind },
                set: { kind in
                    let current = service.trigger.stimulus
                    service.setStimulus(StimulusConfig(kind: kind, intensity: current.intensity, repetitions: current.repetitions))
                }
            )) {
                ForEach(StimulusKind.allCases) { kind in
                    Text(kind.displayName).tag(kind)
                }
            }
            VStack(alignment: .leading) {
                Text("Intensity: \(service.trigger.stimulus.intensity)%")
                Slider(
                    value: Binding(
                        get: { Double(service.trigger.stimulus.intensity) },
                        set: { value in
                            let current = service.trigger.stimulus
                            service.setStimulus(StimulusConfig(
                                kind: current.kind, intensity: Int(value), repetitions: current.repetitions
                            ))
                        }
                    ),
                    in: 0...100, step: 5
                )
            }
        } header: {
            Text("What they get")
        } footer: {
            Text("Your friend's own permissions still apply — the server caps or blocks "
                + "anything they haven't allowed you to send.")
        }
    }

    private var statusSection: some View {
        Section("Status") {
            LabeledContent("Device", value: service.isDeviceConnected ? "Connected" : "Not connected")
            LabeledContent("Listening", value: service.isListening ? "Yes" : "No")
            LabeledContent("Armed", value: service.trigger.isArmed ? "Yes" : "No")
            if let last = service.lastPokeSentAt {
                LabeledContent("Last poke sent", value: last.formatted(.relative(presentation: .named)))
            }
            if let note = service.lastButtonConfigNote {
                Text(note).font(.footnote).foregroundStyle(.secondary)
            }
            if let error = service.lastError {
                Text(error).font(.footnote).foregroundStyle(.red)
            }
        }
    }
}

// MARK: - Which press

/// Picks the press that fires the poke, and makes the device actually report
/// it. Split out so both this and the parent stay small enough to read.
private struct PokeTriggerPressSection: View {
    let service: PokeTriggerService

    var body: some View {
        Section {
            Picker("Button", selection: Binding(
                get: { service.trigger.buttonSlot },
                set: { service.setButtonSlot($0) }
            )) {
                ForEach(DeviceButtonSlot.decodableCases) { slot in
                    Text(slot.displayName).tag(Optional(slot))
                }
                Text("Custom (learn it)").tag(DeviceButtonSlot?.none)
            }
            .accessibilityIdentifier("pokeTriggerButtonPicker")

            if service.trigger.buttonSlot != nil {
                Button {
                    Task { await service.makeButtonReportPresses() }
                } label: {
                    Label("Make this button report presses", systemImage: "antenna.radiowaves.left.and.right")
                }
                .disabled(!service.isDeviceConnected || service.isWritingButtonConfig)
                .accessibilityIdentifier("pokeTriggerReportPressesButton")
            } else {
                learnControls
            }
        } header: {
            Text("Which press")
        } footer: {
            footerText
        }
    }

    @ViewBuilder
    private var learnControls: some View {
        if service.isLearning {
            if let candidate = service.learnCandidate {
                LabeledContent("Captured") {
                    Text(candidate.hexString).font(.footnote.monospaced())
                }
                Button("Use this gesture") { service.confirmLearn() }
                    .accessibilityIdentifier("pokeTriggerUseGestureButton")
            } else {
                Label("Press the button on your Pavlok now…", systemImage: "hand.tap")
                    .foregroundStyle(.orange)
            }
            Button("Cancel", role: .cancel) { service.cancelLearning() }
        } else {
            if let bytes = service.trigger.learnedBytes {
                LabeledContent("Learned") {
                    Text(bytes.map { String(format: "%02X", $0) }.joined(separator: " "))
                        .font(.footnote.monospaced())
                }
                Picker("Matching", selection: Binding(
                    get: { service.trigger.matchMode },
                    set: { service.setMatchMode($0) }
                )) {
                    ForEach(PokeTrigger.MatchMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .accessibilityIdentifier("pokeTriggerMatchModePicker")
                Button("Clear", role: .destructive) { service.clearLearnedGesture() }
            }
            Button {
                service.startLearning()
            } label: {
                Label(
                    service.trigger.learnedBytes == nil ? "Learn a gesture" : "Re-learn gesture",
                    systemImage: "record.circle"
                )
            }
            .disabled(!service.isDeviceConnected)
            .accessibilityIdentifier("pokeTriggerLearnButton")
        }
    }

    private var footerText: Text {
        if !service.isDeviceConnected {
            return Text("Connect your Pavlok to set this up.")
        }
        if service.trigger.buttonSlot != nil {
            return Text("A button set to something the device handles on its own — zap, timer — "
                + "may never tell the phone it was pressed. \"Make this button report presses\" "
                + "sets it to Find my phone, which the phone has to carry out, so the press "
                + "always arrives. The device's own find-my-phone behaviour is ignored here.")
        }
        return Text("Learning captures the raw notification your press produces and matches it "
            + "again later. Use it only if the named buttons above don't fire — they decode the "
            + "press properly and can't be thrown off by a trailing counter byte.")
    }
}

// MARK: - What the device is sending

/// A live view of the last notifications the wearable pushed.
///
/// Without it, "the device never reported the press" and "the app never
/// matched it" are indistinguishable from the outside — which is exactly the
/// confusion this feature keeps causing.
private struct PokeTriggerEventsSection: View {
    let service: PokeTriggerService

    var body: some View {
        Section {
            if service.recentEvents.isEmpty {
                Text(service.isListening
                    ? "Nothing yet. Press a button on the device."
                    : "Not listening — connect the device and enable the trigger.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(service.recentEvents) { event in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.hexString).font(.footnote.monospaced())
                        Text(event.buttonSlot.map { "\($0.displayName) press" } ?? "not a decodable button event")
                            .font(.caption)
                            .foregroundStyle(event.buttonSlot == nil ? Color.secondary : Color.green)
                    }
                }
            }
        } header: {
            Text("Recent device events")
        }
        .accessibilityIdentifier("pokeTriggerEventLog")
    }
}
