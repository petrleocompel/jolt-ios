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

    private var isConnected: Bool { viewModel.connectedDevice != nil }
    private var layout: RemoteDashboardLayout { dependencies.remoteDashboardLayoutService.layout }
    private var firingModes: FiringInteractionSettings { dependencies.firingModeService.settings }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                DeviceHeroCard(
                    device: viewModel.connectedDevice,
                    connectionState: viewModel.connectionState
                )

                ForEach(layout.visible) { kind in
                    widgetCard(for: kind)
                }

                customizeRow
            }
            .padding(16)
        }
        .background(RemoteTheme.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
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
            StimulusIntensityEditorSheet(kind: kind, config: viewModel.stimulusSettings[kind]) { updated in
                viewModel.saveStimulusConfig(updated)
            }
        }
        .sheet(item: $editingAlarm) { alarm in
            AlarmEditView(alarm: alarm) { updated in
                Task { await alarmsViewModel?.save(updated) }
            }
        }
        .sheet(isPresented: $isShowingQuickPokeComposer) {
            quickPokeComposerSheet
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
                    firingMode: firingModes[stimulusKind],
                    onEdit: { editingStimulus = stimulusKind },
                    onFire: { viewModel.fire(viewModel.stimulusSettings[stimulusKind]) }
                )
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

    /// `FriendsViewModel` is only needed to resolve the quick-poke friend by
    /// ID for this one-off override sheet — nothing else on the dashboard
    /// reads it, so it isn't constructed until this is actually tapped.
    private func openQuickPokeComposer() {
        if pokeViewModel == nil {
            pokeViewModel = PokeViewModel(
            repository: dependencies.pokeRepository,
            feedback: dependencies.pokeFeedbackService
        )
        }
        var didCreateFriendsViewModel = false
        if friendsViewModel == nil {
            friendsViewModel = FriendsViewModel(repository: dependencies.friendsRepository)
            didCreateFriendsViewModel = true
        }
        // The passive stream subscription above only replays whatever the
        // launch-time fetch produced. If that fetch already failed (offline,
        // server unreachable), `friends` will never yield again on its own —
        // an explicit retry here is what actually gives this sheet a chance
        // to recover instead of subscribing to a stream that's already dead.
        if didCreateFriendsViewModel, let friendsViewModel {
            Task { await friendsViewModel.refresh() }
        }
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

    @ViewBuilder
    private var quickPokeComposerSheet: some View {
        if let pokeViewModel, let friendsViewModel,
           let friendID = dependencies.quickPokeService.settings.targetFriendID,
           let friend = friendsViewModel.friends.first(where: { $0.id == friendID }) {
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
                .navigationTitle("Poke \(friend.displayName)")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { isShowingQuickPokeComposer = false }
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
        } else if let friendsViewModel, !friendsViewModel.hasLoadedFriends {
            // The friends stream hasn't delivered its first value yet — this
            // sheet's `friendsViewModel` was only just subscribed when it was
            // opened, so an empty/unresolved list here means "still loading,"
            // not "missing." Without this, a real friend would briefly (or,
            // if the fetch never completes, permanently) show as not found.
            QuickPokeLoadingState(friendsViewModel: friendsViewModel)
        } else {
            ContentUnavailableView("Friend not found", systemImage: "person.slash")
        }
    }

    /// Confirmation and errors share one slot: an error supersedes the
    /// success note, because if the write failed then "sent" is a lie.
    @ViewBuilder
    private var actionFeedback: some View {
        if let error = viewModel.lastError {
            InlineBanner(text: error, style: .error)
                .onTapGesture { viewModel.lastError = nil }
                .accessibilityIdentifier("errorFeedback")
                .accessibilityHint("Tap to dismiss")
        } else if let error = dependencies.quickPokeService.lastError {
            InlineBanner(text: error, style: .error)
                .onTapGesture { dependencies.quickPokeService.lastError = nil }
                .accessibilityIdentifier("errorFeedback")
                .accessibilityHint("Tap to dismiss")
        } else if let message = viewModel.lastActionMessage {
            InlineBanner(text: message, style: .success)
                .accessibilityIdentifier("actionFeedback")
        } else if let message = dependencies.pokeFeedbackService.lastSuccessMessage {
            InlineBanner(text: message, style: .success)
                .accessibilityIdentifier("pokeActionFeedback")
        }
    }
}

/// Waits for `friendsViewModel`'s first `friends` emission. A plain spinner
/// would hang forever if the fetch never completes (offline, server
/// unreachable) — there's no other signal that it failed, since the stream
/// just never yields again on its own. After a bounded wait, offer a retry
/// instead of leaving the sheet stuck.
private struct QuickPokeLoadingState: View {
    let friendsViewModel: FriendsViewModel

    @State private var timedOut = false

    var body: some View {
        if timedOut {
            VStack(spacing: 12) {
                Image(systemName: "wifi.slash")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("Couldn't reach the server")
                    .font(.headline)
                Button("Retry") {
                    timedOut = false
                    Task { await friendsViewModel.refresh() }
                }
                .buttonStyle(.borderedProminent)
            }
        } else {
            ProgressView()
                .task {
                    try? await Task.sleep(for: .seconds(8))
                    if !friendsViewModel.hasLoadedFriends { timedOut = true }
                }
        }
    }
}
