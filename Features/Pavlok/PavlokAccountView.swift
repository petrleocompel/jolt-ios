import SwiftUI

/// The optional **Pavlok account** section — a secondary backend alongside the
/// Jolt server, kept visually separate so it's never ambiguous which account a
/// poke goes through.
struct PavlokAccountView: View {
    @State var viewModel: PavlokAccountViewModel

    @State private var email = ""
    @State private var password = ""
    @State private var pokeTarget: PavlokFriend?

    var body: some View {
        List {
            if viewModel.isSignedIn {
                accountSection
                friendsSection
                activitySection
            } else {
                signInSection
            }
            if let error = viewModel.lastError {
                Section {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Pavlok account")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.restore() }
        .refreshable { await viewModel.refresh() }
        .sheet(item: $pokeTarget) { friend in
            PavlokPokeComposer(
                friend: friend,
                permission: viewModel.permission(for: friend),
                onSend: { stimulus in
                    Task { await viewModel.poke(friend, stimulus: stimulus) }
                }
            )
        }
        .accessibilityIdentifier("pavlokAccountScreen")
    }

    // MARK: Sections

    private var signInSection: some View {
        Section {
            TextField("Pavlok email", text: $email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("pavlokEmailField")
            SecureField("Password", text: $password)
                .textContentType(.password)
                .accessibilityIdentifier("pavlokPasswordField")
            Button {
                Task { await viewModel.signIn(email: email, password: password) }
            } label: {
                if viewModel.isLoading {
                    ProgressView()
                } else {
                    Text("Sign in")
                }
            }
            .disabled(email.isEmpty || password.isEmpty || viewModel.isLoading)
            .accessibilityIdentifier("pavlokSignInButton")
        } header: {
            Text("Sign in to Pavlok")
        } footer: {
            Text("Optional, and separate from your Jolt account. Signing in lets you poke "
                + "your Pavlok friends from Jolt. Your password is sent only to Pavlok and "
                + "isn't stored — the session token is kept in the keychain.")
        }
    }

    private var accountSection: some View {
        Section {
            LabeledContent("Signed in as", value: viewModel.account?.displayName ?? "—")
            Button("Sign out", role: .destructive) { viewModel.signOut() }
                .accessibilityIdentifier("pavlokSignOutButton")
        } header: {
            Text("Account")
        }
    }

    private var friendsSection: some View {
        Section {
            if viewModel.friends.isEmpty {
                Text(viewModel.isLoading ? "Loading…" : "No Pavlok friends found.")
                    .foregroundStyle(.secondary)
            }
            ForEach(viewModel.friends) { friend in
                let grant = viewModel.permission(for: friend)
                Button {
                    pokeTarget = friend
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(friend.displayName)
                            Text(allowanceSummary(grant))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "hand.tap")
                            .foregroundStyle(canPoke(grant) ? Color.accentColor : Color.secondary)
                    }
                }
                .disabled(!canPoke(grant))
            }
        } header: {
            Text("Pavlok friends")
        } footer: {
            Text("You can only send what each friend has allowed. Zap intensity is capped "
                + "by their limit.")
        }
    }

    private var activitySection: some View {
        Section {
            if viewModel.activity.isEmpty {
                Text("Nothing logged yet.").foregroundStyle(.secondary)
            }
            ForEach(viewModel.activity.prefix(20)) { entry in
                HStack {
                    Text(entry.kind?.displayName ?? entry.rawName)
                    Spacer()
                    Text(entry.timestamp, format: .dateTime.month().day().hour().minute())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Device activity")
        } footer: {
            // This is the honest bit: the journal has no sender, so it cannot
            // say a friend poked you. See docs/PAVLOK-API.md.
            Text("This is your wearable's own log of stimuli it fired, uploaded to Pavlok. "
                + "It doesn't record who caused each one, so a friend's poke looks the same "
                + "as pressing the button yourself. Pavlok delivers incoming pokes only to "
                + "their own app, so Jolt can't show them.")
        }
    }

    // MARK: Helpers

    private func canPoke(_ grant: PavlokPokePermission) -> Bool {
        grant.canZap || grant.canVibrate || grant.canChime
    }

    private func allowanceSummary(_ grant: PavlokPokePermission) -> String {
        var allowed: [String] = []
        if grant.canVibrate { allowed.append("vibe") }
        if grant.canChime { allowed.append("beep") }
        if grant.canZap { allowed.append("zap ≤\(grant.maxZapValue)%") }
        return allowed.isEmpty ? "Hasn't allowed pokes" : "Allows " + allowed.joined(separator: ", ")
    }
}

/// Picks a stimulus for one Pavlok friend, offering only what they permit.
private struct PavlokPokeComposer: View {
    let friend: PavlokFriend
    let permission: PavlokPokePermission
    let onSend: (StimulusConfig) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var kind: StimulusKind = .vibe
    @State private var intensity: Double = 30

    private var allowedKinds: [StimulusKind] {
        StimulusKind.allCases.filter { permission.allows($0) }
    }

    private var maxIntensity: Double {
        Double(permission.maxIntensity(for: kind))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Stimulus") {
                    Picker("Type", selection: $kind) {
                        ForEach(allowedKinds) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    VStack(alignment: .leading) {
                        Text("Intensity: \(Int(intensity))%")
                        Slider(value: $intensity, in: 0...max(1, maxIntensity), step: 5)
                    }
                    if kind == .zap {
                        Text("Capped at \(permission.maxZapValue)% by \(friend.displayName).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Section {
                    Button("Send poke") {
                        onSend(StimulusConfig(kind: kind, intensity: Int(intensity), repetitions: 1))
                        dismiss()
                    }
                    .accessibilityIdentifier("pavlokSendPokeButton")
                }
            }
            .navigationTitle("Poke \(friend.displayName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                if let first = allowedKinds.first { kind = first }
            }
            .onChange(of: kind) { _, _ in
                intensity = min(intensity, maxIntensity)
            }
        }
    }
}
