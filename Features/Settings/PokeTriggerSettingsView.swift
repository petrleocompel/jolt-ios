import SwiftUI

/// Configures the "poke a friend from your Pavlok" trigger (Approach A).
///
/// Flow: pick a friend and a stimulus, then **Learn a gesture** — with the
/// device connected, press the button you want to use and the app records the
/// event it produces. From then on, that press sends the poke.
struct PokeTriggerSettingsView: View {
    @State var service: PokeTriggerService
    let friendsRepository: FriendsRepository

    @State private var friends: [Friend] = []
    @State private var showLearnConfirm = false

    private var trigger: PokeTrigger { service.trigger }

    var body: some View {
        List {
            enableSection
            if trigger.isEnabled {
                friendSection
                stimulusSection
                gestureSection
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
                        if let id, let friend = friends.first(where: { $0.id == id }) {
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
                    let s = service.trigger.stimulus
                    service.setStimulus(StimulusConfig(kind: kind, intensity: s.intensity, repetitions: s.repetitions))
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
                            let s = service.trigger.stimulus
                            service.setStimulus(StimulusConfig(
                                kind: s.kind, intensity: Int(value), repetitions: s.repetitions
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

    private var gestureSection: some View {
        Section {
            if service.isLearning {
                if let candidate = service.learnCandidate {
                    LabeledContent("Captured") {
                        Text(candidate.hexString).font(.footnote.monospaced())
                    }
                    Button("Use this gesture") {
                        service.confirmLearn()
                    }
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
        } header: {
            Text("Gesture")
        } footer: {
            if !service.isDeviceConnected {
                Text("Connect your Pavlok to learn a gesture.")
            } else {
                Text("We match the exact event your press produces, so no firmware decoding is needed.")
            }
        }
    }

    private var statusSection: some View {
        Section("Status") {
            LabeledContent("Device", value: service.isDeviceConnected ? "Connected" : "Not connected")
            LabeledContent("Armed", value: service.trigger.isArmed ? "Yes" : "No")
            if let last = service.lastPokeSentAt {
                LabeledContent("Last poke sent", value: last.formatted(.relative(presentation: .named)))
            }
            if let error = service.lastError {
                Text(error).font(.footnote).foregroundStyle(.red)
            }
        }
    }
}
