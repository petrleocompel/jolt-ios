import SwiftUI

struct AddFriendView: View {
    let viewModel: FriendsViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var handleInput = ""
    @State private var codeInput = ""
    @State private var isScanning = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Add by handle") {
                    TextField("@handle", text: $handleInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("addFriendHandleField")
                    Button("Send request") {
                        Task {
                            await viewModel.sendRequest(handle: handleInput)
                            if viewModel.lastError == nil { dismiss() }
                        }
                    }
                    .disabled(handleInput.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                Section("Add by invite code") {
                    TextField("Invite code", text: $codeInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Send request") {
                        Task {
                            await viewModel.sendRequest(inviteCode: codeInput)
                            if viewModel.lastError == nil { dismiss() }
                        }
                    }
                    .disabled(codeInput.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button("Scan a QR code instead") { isScanning = true }
                }

                Section("Your code") {
                    VStack(spacing: 12) {
                        QRCodeView(content: viewModel.myInviteCode)
                            .frame(width: 180, height: 180)
                        Text("@\(viewModel.myHandle)").font(.headline)
                        Text(viewModel.myInviteCode)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }

                if let error = viewModel.lastError {
                    Section {
                        Text(error).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Add friend")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .sheet(isPresented: $isScanning) {
                QRScannerView { scanned in
                    codeInput = scanned
                    isScanning = false
                }
            }
        }
    }
}
