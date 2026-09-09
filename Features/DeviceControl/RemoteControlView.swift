import SwiftUI

enum RemoteDestination: Hashable {
    case deviceDetail
}

/// Hosts the Remote tab's navigation: the dashboard by default, pushing to
/// device detail. Customize and stimulus/alarm editing are sheets owned by
/// `RemoteDashboardView` itself.
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
    }
}
