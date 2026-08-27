import SwiftUI

struct AuthView: View {
    let viewModel: AuthViewModel

    private enum Mode: String, CaseIterable {
        case logIn = "Log In"
        case signUp = "Sign Up"
    }

    @State private var mode: Mode = .logIn
    @State private var email = ""
    @State private var password = ""
    @State private var handle = ""
    @State private var displayName = ""

    var body: some View {
        NavigationStack {
            Form {
                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)

                Section {
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("emailField")
                    SecureField("Password", text: $password)
                        .accessibilityIdentifier("passwordField")
                    if mode == .signUp {
                        TextField("Handle (e.g. alice)", text: $handle)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        TextField("Display name", text: $displayName)
                    }
                }

                if let error = viewModel.lastError {
                    Section {
                        Text(error).foregroundStyle(.red)
                    }
                }

                Section {
                    Button(mode == .logIn ? "Log In" : "Sign Up", action: submit)
                        .disabled(!isValid)
                        .accessibilityIdentifier("authSubmitButton")
                }
            }
            .disabled(viewModel.isBusy)
            .overlay {
                if viewModel.isBusy { ProgressView() }
            }
            .navigationTitle("Friends")
        }
    }

    private var isValid: Bool {
        guard !email.isEmpty, !password.isEmpty else { return false }
        if mode == .signUp { return !handle.isEmpty && !displayName.isEmpty }
        return true
    }

    private func submit() {
        switch mode {
        case .logIn:
            viewModel.logIn(email: email, password: password)
        case .signUp:
            viewModel.signUp(email: email, password: password, handle: handle, displayName: displayName)
        }
    }
}
