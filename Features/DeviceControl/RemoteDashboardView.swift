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
    private var firingMode: FiringInteractionMode { dependencies.firingModeService.mode }

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
        .task {
            if pokeViewModel == nil {
                pokeViewModel = PokeViewModel(repository: dependencies.pokeRepository)
            }
            if friendsViewModel == nil {
                friendsViewModel = FriendsViewModel(repository: dependencies.friendsRepository)
            }
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
                    firingMode: firingMode,
                    onEdit: { editingStimulus = stimulusKind },
                    onFire: { viewModel.fire(viewModel.stimulusSettings[stimulusKind]) }
                )
            }
        case .quickPoke:
            if dependencies.quickPokeService.settings.isConfigured {
                QuickPokeCard(
                    settings: dependencies.quickPokeService.settings,
                    firingMode: firingMode,
                    lastError: dependencies.quickPokeService.lastError,
                    onFire: { dependencies.quickPokeService.sendQuickPoke() },
                    onOpenComposer: { isShowingQuickPokeComposer = true }
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
                    PokeComposerCard(friend: friend, pokeViewModel: pokeViewModel, firingMode: firingMode)
                        .padding()
                }
                .navigationTitle("Poke \(friend.displayName)")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { isShowingQuickPokeComposer = false }
                    }
                }
            }
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
        } else if let message = viewModel.lastActionMessage {
            InlineBanner(text: message, style: .success)
                .accessibilityIdentifier("actionFeedback")
        }
    }
}
