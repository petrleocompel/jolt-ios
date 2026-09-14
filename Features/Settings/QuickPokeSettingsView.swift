import SwiftUI

/// Configures the one-tap "quick poke" shortcut shown on the Remote tab: pick
/// a friend and a stimulus once here, then fire it from Remote without
/// digging into Friends each time.
struct QuickPokeSettingsView: View {
    @State var service: QuickPokeService
    let friendsRepository: FriendsRepository

    @State private var friends: [Friend] = []

    private var settings: QuickPokeSettings { service.settings }

    var body: some View {
        List {
            enableSection
            if settings.isEnabled {
                friendSection
                stimulusSection
                statusSection
            }
        }
        .navigationTitle("Quick Poke")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            for await list in friendsRepository.friends {
                friends = list
            }
        }
        .accessibilityIdentifier("quickPokeSettingsScreen")
    }

    // MARK: Sections

    private var enableSection: some View {
        Section {
            Toggle("Quick poke on Remote", isOn: Binding(
                get: { service.settings.isEnabled },
                set: { service.setEnabled($0) }
            ))
            .accessibilityIdentifier("quickPokeEnableToggle")
        } footer: {
            Text("Adds a one-tap poke button to the Remote tab for the friend you choose below.")
        }
    }

    private var friendSection: some View {
        Section("Who to poke") {
            if friends.isEmpty {
                Text("Add a friend first — pokes go to someone on your friends list.")
                    .foregroundStyle(.secondary)
            } else {
                Picker("Friend", selection: Binding(
                    get: { service.settings.targetFriendID },
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
                .accessibilityIdentifier("quickPokeFriendPicker")
            }
        }
    }

    private var stimulusSection: some View {
        Section {
            Picker("Stimulus", selection: Binding(
                get: { service.settings.stimulus.kind },
                set: { kind in
                    let current = service.settings.stimulus
                    service.setStimulus(StimulusConfig(kind: kind, intensity: current.intensity, repetitions: current.repetitions))
                }
            )) {
                ForEach(StimulusKind.allCases) { kind in
                    Text(kind.displayName).tag(kind)
                }
            }
            VStack(alignment: .leading) {
                Text("Intensity: \(service.settings.stimulus.intensity)%")
                Slider(
                    value: Binding(
                        get: { Double(service.settings.stimulus.intensity) },
                        set: { value in
                            let current = service.settings.stimulus
                            service.setStimulus(StimulusConfig(
                                kind: current.kind, intensity: Int(value), repetitions: current.repetitions
                            ))
                        }
                    ),
                    in: 0...100, step: 5
                )
            }
            Stepper(
                "Repetitions: \(service.settings.stimulus.repetitions)",
                value: Binding(
                    get: { service.settings.stimulus.repetitions },
                    set: { value in
                        let current = service.settings.stimulus
                        service.setStimulus(StimulusConfig(kind: current.kind, intensity: current.intensity, repetitions: value))
                    }
                ),
                in: 1...5
            )
        } header: {
            Text("What they get")
        } footer: {
            Text("Your friend's own permissions still apply — the server caps or blocks "
                + "anything they haven't allowed you to send.")
        }
    }

    private var statusSection: some View {
        Section("Status") {
            LabeledContent("Ready", value: settings.isConfigured ? "Yes" : "No")
            if let last = service.lastPokeSentAt {
                LabeledContent("Last poke sent", value: last.formatted(.relative(presentation: .named)))
            }
            if let error = service.lastError {
                Text(error).font(.footnote).foregroundStyle(.red)
            }
        }
    }
}
