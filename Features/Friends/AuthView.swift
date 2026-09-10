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
            List {
                Section {
                    VStack(spacing: 8) {
                        Image(systemName: "person.2.circle.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(Color.accentColor)
                        Text("Connect with friends")
                            .font(.title3.bold())
                        Text("Log in or create an account to add friends and send pokes.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)

                    Picker("Mode", selection: $mode) {
                        ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                Section {
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("emailField")
                    SecureField("Password", text: $password)
                        .textContentType(mode == .signUp ? .newPassword : .password)
                        .accessibilityIdentifier("passwordField")
                    if mode == .signUp {
                        TextField("Handle (e.g. alice)", text: $handle)
                            .textContentType(.username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        TextField("Display name", text: $displayName)
                            .textContentType(.name)
                    }
                }

                Section {
                    Button(action: submit) {
                        HStack {
                            Spacer()
                            if viewModel.isBusy {
                                ProgressView()
                            } else {
                                Text(mode == .logIn ? "Log In" : "Sign Up")
                                    .bold()
                            }
                            Spacer()
                        }
                    }
                    .disabled(!isValid || viewModel.isBusy)
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("authSubmitButton")
                }
                .listRowBackground(Color.clear)
            }
            .navigationTitle("Friends")
            .errorBanner(viewModel.lastError) { viewModel.lastError = nil }
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
