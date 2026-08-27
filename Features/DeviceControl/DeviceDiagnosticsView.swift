import SwiftUI

struct DeviceDiagnosticsView: View {
    let viewModel: DeviceControlViewModel
    @State private var info: DeviceInfo?
    @State private var isLoading = false

    var body: some View {
        List {
            if let info {
                LabeledContent("Model", value: info.modelNumber ?? "—")
                LabeledContent("Serial", value: info.serialNumber ?? "—")
                LabeledContent("Firmware", value: info.firmwareRevision ?? "—")
                LabeledContent("Hardware", value: info.hardwareRevision ?? "—")
                LabeledContent("Software", value: info.softwareRevision ?? "—")
                LabeledContent("Manufacturer", value: info.manufacturer ?? "—")
                LabeledContent("Battery", value: info.batteryLevelPercent.map { "\($0)%" } ?? "—")
            } else if isLoading {
                ProgressView()
            }
        }
        .navigationTitle("Diagnostics")
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        info = try? await viewModel.readDeviceInfo()
    }
}
