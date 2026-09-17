import SwiftUI

/// The Remote tab's home screen — device status pinned first, then a
/// reorderable/hideable list of widgets (one per stimulus, quick poke, next
/// alarm, recent activity). Everything that worked in the old plain-`List`
/// Remote screen still works here: firing a stimulus, editing its saved
/// intensity/repetitions, quick poke, disconnecting, reaching diagnostics and
/// button configuration (now one level deeper, via the device card).
struct RemoteDashboardView: View {
    let viewModel: DeviceControlViewModel

    @Environment(AppDependencies.self) private var dependencies

    @State private var pokeViewModel: PokeViewModel?
    @State private var friendsViewModel: FriendsViewModel?
    @State private var alarmsViewModel: AlarmsViewModel?

    @State private var editingStimulus: StimulusKind?
    @State private var editingAlarm: Alarm?
    @State private var isShowingCustomize = false
    @State private var isShowingQuickPokeComposer = false
    @State private var isShowingPairSheet = false

    private var isConnected: Bool { viewModel.connectedDevice != nil }
    private var layout: RemoteDashboardLayout { dependencies.remoteDashboardLayoutService.layout }
    private var firingModes: FiringInteractionSettings { dependencies.firingModeService.settings }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                DeviceHeroCard(
                    device: viewModel.connectedDevice,
                    connectionState: viewModel.connectionState,
                    hasPairedDevice: viewModel.hasPairedDevice,
                    pairedDeviceName: viewModel.pairedDeviceName,
                    onPairDevice: { isShowingPairSheet = true },
                    onTryAgain: { viewModel.reconnect() }
                )

                ForEach(layout.visible) { kind in
                    widgetCard(for: kind)
                }

                customizeRow
            }
            .padding(16)
        }
        .background(RemoteTheme.background.ignoresSafeArea())
        .navigationTitle("Remote")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("remoteControlScreen")
        .safeAreaInset(edge: .bottom) { actionFeedback }
        .animation(.snappy, value: viewModel.lastActionMessage)
        .animation(.snappy, value: viewModel.lastError)
        .animation(.snappy, value: dependencies.pokeFeedbackService.lastSuccessMessage)
        .animation(.snappy, value: dependencies.quickPokeService.lastError)
        .task {
            // Lazy on purpose: Friends' own streams already have one
            // subscriber apiece the moment that tab is visited, and adding
            // more from a tab that's on screen at every launch — whether or
            // not anything here actually needs them — only grows the set of
            // concurrent subscribers `FriendsRepository`/`PokeRepository`
            // have to fan out to. Only construct what the widgets actually
            // on screen need.
            ensurePokeViewModelIfNeeded()
            if alarmsViewModel == nil {
                let model = AlarmsViewModel(
                    alarmRepository: dependencies.alarmRepository,
                    deviceRepository: dependencies.deviceRepository,
                    phoneAlarmScheduler: dependencies.phoneAlarmScheduler
                )
                alarmsViewModel = model
                await model.load()
            }
        }
        .onChange(of: layout.visible) { _, _ in ensurePokeViewModelIfNeeded() }
        .sheet(isPresented: $isShowingCustomize) {
            RemoteCustomizeView(
                layoutService: dependencies.remoteDashboardLayoutService,
                isQuickPokeConfigured: dependencies.quickPokeService.settings.isConfigured
            )
        }
        .sheet(item: $editingStimulus) { kind in
            // Sheets from the always-dark Remote tab inherit its dark
            // environment but not its presentation, so each one asks for
            // dark itself — scoped to that sheet, it doesn't reach the window.
            StimulusIntensityEditorSheet(kind: kind, config: viewModel.stimulusSettings[kind]) { updated in
                viewModel.saveStimulusConfig(updated)
            }
            .preferredColorScheme(.dark)
        }
        .sheet(item: $editingAlarm) { alarm in
            AlarmEditView(alarm: alarm) { updated in
                Task { await alarmsViewModel?.save(updated) }
            }
            .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $isShowingPairSheet) {
            PairDeviceSheet(viewModel: viewModel)
                .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $isShowingQuickPokeComposer) {
            QuickPokeComposerSheet(
                targetFriendID: dependencies.quickPokeService.settings.targetFriendID,
                targetFriendName: dependencies.quickPokeService.settings.targetFriendName,
                onClose: { isShowingQuickPokeComposer = false }
            )
            .preferredColorScheme(.dark)
        }
    }

    @ViewBuilder
    private func widgetCard(for kind: RemoteWidgetKind) -> some View {
        switch kind {
        case .zap, .vibe, .beep:
            if let stimulusKind = kind.stimulusKind {
                StimulusRow(
                    kind: stimulusKind,
                    config: viewModel.stimulusSettings[stimulusKind],
                    isEnabled: isConnected,
                    deviceName: viewModel.connectedDevice?.name,
                    firingMode: firingModes[stimulusKind],
                    onEdit: { editingStimulus = stimulusKind },
                    onFire: { viewModel.fire(viewModel.stimulusSettings[stimulusKind]) },
                    onUnavailable: { viewModel.fire(viewModel.stimulusSettings[stimulusKind]) }
                )
                // Dimmed, not hidden: the saved intensity stays visible and
                // editable, it just can't fire until a device is back.
                .opacity(isConnected ? 1 : 0.4)
            }
        case .quickPoke:
            if dependencies.quickPokeService.settings.isConfigured {
                QuickPokeCard(
                    settings: dependencies.quickPokeService.settings,
                    firingMode: firingModes[dependencies.quickPokeService.settings.stimulus.kind],
                    lastError: dependencies.quickPokeService.lastError,
                    feedback: dependencies.pokeFeedbackService,
                    onFire: { dependencies.quickPokeService.sendQuickPoke() },
                    onOpenComposer: openQuickPokeComposer
                )
            }
        case .nextAlarm:
            if let (alarm, occursAt) = nextAlarm {
                NextAlarmCard(alarm: alarm, occursAt: occursAt) { editingAlarm = alarm }
            }
        case .recentActivity:
            if let pokeViewModel, !pokeViewModel.activity.isEmpty {
                RecentActivityCard(events: Array(pokeViewModel.activity.prefix(2)))
            }
        }
    }

    /// Only the "Recent activity" widget needs a live `activity` subscriber
    /// on its own; the composer sheet brings up its own via
    /// `openQuickPokeComposer` when it's actually opened.
    private func ensurePokeViewModelIfNeeded() {
        guard pokeViewModel == nil, layout.visible.contains(.recentActivity) else { return }
        pokeViewModel = PokeViewModel(
            repository: dependencies.pokeRepository,
            feedback: dependencies.pokeFeedbackService
        )
    }

    /// The sheet owns the view models it needs (see `QuickPokeComposerSheet`)
    /// rather than being handed them from here: assigning `@State` and
    /// presenting in the same turn meant the sheet's content was built
    /// against the pre-assignment value — a nil `FriendsViewModel`, which
    /// read as "Friend not found" no matter how healthy the friends list was.
    private func openQuickPokeComposer() {
        isShowingQuickPokeComposer = true
    }

    private var nextAlarm: (Alarm, Date)? {
        guard let alarms = alarmsViewModel?.alarms else { return nil }
        return alarms
            .compactMap { alarm -> (Alarm, Date)? in
                guard let date = alarm.nextOccurrence() else { return nil }
                return (alarm, date)
            }
            .min { $0.1 < $1.1 }
    }

    private var customizeRow: some View {
        Button {
            isShowingCustomize = true
        } label: {
            Text("Customize home screen")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.5))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .foregroundStyle(.white.opacity(0.18))
        )
    }

    /// Confirmation and errors share one slot: an error supersedes the
    /// success note, because if the write failed then "sent" is a lie.
    @ViewBuilder
    private var actionFeedback: some View {
        if let error = viewModel.lastError {
            InlineBanner(text: error, style: .error) { viewModel.lastError = nil }
                .accessibilityIdentifier("errorFeedback")
        } else if let error = dependencies.quickPokeService.lastError {
            InlineBanner(text: error, style: .error) { dependencies.quickPokeService.lastError = nil }
                .accessibilityIdentifier("errorFeedback")
        } else if let message = viewModel.lastActionMessage {
            InlineBanner(text: message, style: .success)
                .accessibilityIdentifier("actionFeedback")
        } else if let message = dependencies.pokeFeedbackService.lastSuccessMessage {
            InlineBanner(text: message, style: .success)
                .accessibilityIdentifier("pokeActionFeedback")
        }
    }
}

/// The Remote dashboard's one-off poke composer, pre-loaded with the
/// Settings → Quick Poke friend. Presents the same `PokeComposerCard` the
/// Friends tab uses, so this is the full poke flow, not a reduced one.
///
/// Builds its own view models in `.task` instead of receiving them from the
/// dashboard. The dashboard used to create them and set `isPresented` in the
/// same synchronous call, and SwiftUI built the sheet's content from the
/// state as it was *before* that assignment — a nil `FriendsViewModel` —
/// which fell through to "Friend not found" permanently, even with the
/// friend present and the server healthy.
private struct QuickPokeComposerSheet: View {
    let targetFriendID: Friend.ID?
    let targetFriendName: String?
    let onClose: () -> Void

    @Environment(AppDependencies.self) private var dependencies

    @State private var friendsViewModel: FriendsViewModel?
    @State private var pokeViewModel: PokeViewModel?

    var body: some View {
        content
            .task {
                if pokeViewModel == nil {
                    pokeViewModel = PokeViewModel(
                        repository: dependencies.pokeRepository,
                        feedback: dependencies.pokeFeedbackService
                    )
                }
                guard friendsViewModel == nil else { return }
                let model = FriendsViewModel(repository: dependencies.friendsRepository)
                friendsViewModel = model
                // The stream only replays what the launch-time fetch produced;
                // if that failed there is nothing to replay and no retry of
                // its own, so ask for a fresh one.
                await model.refresh()
            }
    }

    @ViewBuilder
    private var content: some View {
        if let pokeViewModel, let friendsViewModel, let targetFriendID,
           let friend = friendsViewModel.friends.first(where: { $0.id == targetFriendID }) {
            composer(friend: friend, pokeViewModel: pokeViewModel)
        } else if friendsViewModel?.hasLoadedFriends != true {
            // Still loading: an empty/unresolved list here does not yet mean
            // the friend is missing.
            QuickPokeLoadingState(friendsViewModel: friendsViewModel, onClose: onClose)
        } else {
            notFound
        }
    }

    private func composer(friend: Friend, pokeViewModel: PokeViewModel) -> some View {
        NavigationStack {
            ScrollView {
                PokeComposerCard(
                    friend: friend,
                    pokeViewModel: pokeViewModel,
                    firingModeService: dependencies.firingModeService,
                    draftStore: dependencies.friendPokeDraftStore,
                    feedback: dependencies.pokeFeedbackService
                )
                .padding()
            }
            .accessibilityIdentifier("quickPokeComposerSheet")
            .navigationTitle("Poke \(friend.displayName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: onClose)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let message = dependencies.pokeFeedbackService.lastSuccessMessage {
                    InlineBanner(text: message, style: .success)
                        .accessibilityIdentifier("pokeActionFeedback")
                }
            }
            .animation(.snappy, value: dependencies.pokeFeedbackService.lastSuccessMessage)
        }
    }

    /// The saved target ID genuinely matches nobody in the current friends
    /// list — e.g. they removed you, or it was configured against a different
    /// account. Re-picking in Quick Poke settings writes a fresh, valid ID.
    private var notFound: some View {
        let name = targetFriendName ?? "This friend"
        return NavigationStack {
            ScrollView {
                StatusCard(
                    tint: .orange,
                    eyebrow: "FRIEND NOT FOUND",
                    message: "\(name) is no longer on your friends list. Send a new request, "
                        + "or pick someone else in Settings → Quick poke."
                ) {
                    StatusCardButton(title: "Close", action: onClose)
                }
                .padding()
            }
            .navigationTitle(targetFriendName.map { "Poke \($0)" } ?? "Quick poke")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: onClose)
                }
            }
            .accessibilityIdentifier("quickPokeFriendNotFound")
        }
    }
}

/// Waits for `friendsViewModel`'s first `friends` emission. A plain spinner
/// would hang forever if the fetch never completes (offline, server
/// unreachable) — there's no other signal that it failed, since the stream
/// just never yields again on its own. After a bounded wait, offer a retry
/// instead of leaving the sheet stuck.
private struct QuickPokeLoadingState: View {
    let friendsViewModel: FriendsViewModel?
    let onClose: () -> Void

    @State private var timedOut = false

    var body: some View {
        if timedOut {
            StatusCard(
                tint: .red,
                eyebrow: "COULDN'T REACH THE SERVER",
                message: "Your friends list didn't load, so nothing can be sent yet. Check your connection and try again."
            ) {
                HStack(spacing: 10) {
                    StatusCardButton(title: "Retry", fill: RemoteTheme.violet, ink: .white) {
                        timedOut = false
                        Task { await friendsViewModel?.refresh() }
                    }
                    StatusCardButton(title: "Close", action: onClose)
                }
            }
            .padding()
        } else {
            ProgressView()
                .accessibilityIdentifier("quickPokeComposerLoading")
                .task {
                    try? await Task.sleep(for: .seconds(8))
                    if friendsViewModel?.hasLoadedFriends != true { timedOut = true }
                }
        }
    }
}
