import SwiftUI

enum RemoteDestination: Hashable {
    case deviceDetail
}

/// Hosts the Remote tab's navigation: the dashboard by default, pushing to
/// device detail. Customize and stimulus/alarm editing are sheets owned by
/// `RemoteDashboardView` itself.
///
/// The Remote tab is always dark. That's set here as an *environment* value
/// scoped to this stack, not with `preferredColorScheme`: the latter is a
/// request to the whole window, so inside a `TabView` it turned every tab
/// dark and light mode never showed anywhere once you'd seen Remote.
struct RemoteControlView: View {
    let viewModel: DeviceControlViewModel

    var body: some View {
        NavigationStack {
            RemoteDashboardView(viewModel: viewModel)
                .navigationDestination(for: RemoteDestination.self) { destination in
                    switch destination {
                    case .deviceDetail:
                        RemoteDeviceDetailView(viewModel: viewModel)
                    }
                }
        }
        .environment(\.colorScheme, .dark)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
}
