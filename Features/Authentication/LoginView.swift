import SwiftUI

struct LoginView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(NavidromeSession.self) private var session

    @State private var serverURL = ""
    @State private var username = ""
    @State private var password = ""
    @FocusState private var focusedField: Field?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    header
                    credentialsForm
                    connectButton
                }
                .frame(maxWidth: 560)
                .padding(.horizontal, 24)
                .padding(.vertical, 40)
            }
            .background(loginBackground.ignoresSafeArea())
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("连接音乐库")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            guard serverURL.isEmpty, username.isEmpty, password.isEmpty else {
                return
            }
            serverURL = settings.serverURL
            username = settings.username
            password = settings.password
            focusedField = serverURL.isEmpty ? .server : nil
        }
    }

    private var header: some View {
        VStack(spacing: 14) {
            Image("BrandIcon")
                .resizable()
                .scaledToFill()
                .frame(width: 112, height: 112)
                .clipShape(RoundedRectangle(cornerRadius: 28))
                .shadow(color: .purple.opacity(0.28), radius: 22, y: 12)
                .accessibilityHidden(true)

            Text("NaviLyrics")
                .font(.largeTitle.bold())
            Text("验证 Navidrome 服务器后才能进入音乐库")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var credentialsForm: some View {
        VStack(spacing: 0) {
            loginField(
                title: "服务器地址",
                systemImage: "server.rack"
            ) {
                TextField("192.168.1.10:4533", text: $serverURL)
                    .textContentType(.URL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .server)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .username }
            }

            Divider().padding(.leading, 48)

            loginField(title: "用户名", systemImage: "person.fill") {
                TextField("用户名", text: $username)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .username)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .password }
            }

            Divider().padding(.leading, 48)

            loginField(title: "密码", systemImage: "lock.fill") {
                SecureField("密码", text: $password)
                    .textContentType(.password)
                    .focused($focusedField, equals: .password)
                    .submitLabel(.go)
                    .onSubmit { connect() }
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(.primary.opacity(0.08), lineWidth: 0.5)
        }
    }

    private func loginField<FieldContent: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> FieldContent
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 22)
                .accessibilityHidden(true)
            content()
                .accessibilityLabel(title)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 56)
    }

    private var connectButton: some View {
        VStack(spacing: 14) {
            if let errorMessage = session.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Button(action: connect) {
                HStack(spacing: 10) {
                    if session.isConnecting {
                        ProgressView().tint(.white)
                    }
                    Text(session.isConnecting ? "正在验证…" : "连接并进入音乐库")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
            }
            .buttonStyle(.borderedProminent)
            .tint(.purple)
            .disabled(!canSubmit || session.isConnecting)

            Text("支持 http://、https:// 和局域网 IP 地址")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var loginBackground: some View {
        LinearGradient(
            colors: [
                Color.purple.opacity(0.12),
                Color.pink.opacity(0.06),
                Color.clear,
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var canSubmit: Bool {
        !serverURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !password.isEmpty
    }

    private func connect() {
        guard canSubmit, !session.isConnecting else { return }
        focusedField = nil
        Task {
            await session.signIn(
                serverURL: serverURL,
                username: username,
                password: password,
                settings: settings
            )
        }
    }

    private enum Field: Hashable {
        case server
        case username
        case password
    }
}
