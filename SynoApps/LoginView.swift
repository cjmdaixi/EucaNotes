import SwiftUI

private enum LoginConnectionMode: String, CaseIterable, Identifiable {
    case direct
    case quickConnect

    var id: String { rawValue }
    var title: String { self == .direct ? "服务器地址" : "QuickConnect" }
}

struct LoginView: View {
    @Environment(LibraryStore.self) private var store
    @State private var server = UserDefaults.standard.string(forKey: "last-server") ?? ""
    @State private var quickConnectID = UserDefaults.standard.string(forKey: "quickconnect-id") ?? ""
    @State private var connectionMode: LoginConnectionMode = .direct
    @State private var account = ""
    @State private var password = ""
    @State private var otp = ""
    @State private var useHTTPS = true
    @State private var rememberDevice = true
    @FocusState private var focusedField: Field?

    private enum Field { case server, account, password, otp }

    private var activeServer: String {
        connectionMode == .direct ? server : quickConnectID
    }

    var body: some View {
        @Bindable var store = store
        ScrollView {
            VStack(spacing: 0) {
                SynoMark(size: 68)
                    .padding(.bottom, 20)
                Text("Note Station")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                Text("连接群晖，带走你的每一则灵感")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 7)

                VStack(alignment: .leading, spacing: 18) {
                    if !store.requiresOTP {
                        Picker("连接方式", selection: $connectionMode) {
                            ForEach(LoginConnectionMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("connection-mode-picker")
                        field(
                            title: connectionMode.title,
                            prompt: connectionMode == .direct ? "nas.example.com:5001" : "输入 QuickConnect ID",
                            text: Binding(get: { activeServer }, set: { value in
                                if connectionMode == .direct { server = value } else { quickConnectID = value }
                            }),
                            field: .server
                        )
                        .keyboardType(connectionMode == .direct ? .URL : .asciiCapable)
                        HStack {
                            Label(connectionMode == .direct ? "使用 HTTPS 安全连接" : "优先使用 HTTPS 直连", systemImage: "lock.shield")
                                .font(.subheadline)
                            Spacer()
                            Toggle("使用 HTTPS", isOn: $useHTTPS)
                                .labelsHidden()
                        }
                        if connectionMode == .quickConnect {
                            Label("自动尝试直连；不可达时使用官方中继", systemImage: "arrow.triangle.branch")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        field(title: "账户", prompt: "DSM 账户", text: $account, field: .account)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("密码")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                            SecureField("DSM 密码", text: $password)
                                .textContentType(.password)
                                .focused($focusedField, equals: .password)
                                .submitLabel(.go)
                                .onSubmit(login)
                                .padding(.horizontal, 14)
                                .frame(height: 48)
                                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    } else {
                        VStack(spacing: 10) {
                            Image(systemName: "lock.badge.clock")
                                .font(.system(size: 34))
                                .foregroundStyle(AppTheme.accent)
                            Text("输入二次验证码")
                                .font(.title3.bold())
                            Text("请打开认证器，输入 6 位验证码以继续登录。")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        field(title: "验证码", prompt: "000000", text: $otp, field: .otp)
                            .keyboardType(.numberPad)
                        Toggle("信任此设备，下次免验证码", isOn: $rememberDevice)
                            .font(.subheadline)
                    }

                    Button(action: login) {
                        HStack(spacing: 9) {
                            if store.isLoggingIn { ProgressView().tint(.white) }
                            Text(store.isLoggingIn ? store.loginStatus : (store.requiresOTP ? "验证并登录" : "登录"))
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.accent)
                    .controlSize(.large)
                    .disabled(store.isLoggingIn || activeServer.isEmpty || account.isEmpty || password.isEmpty || (store.requiresOTP && otp.isEmpty))
                    .accessibilityIdentifier("login-button")

                    if store.requiresOTP {
                        Button("返回账户登录") { store.requiresOTP = false; otp = "" }
                            .font(.subheadline)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(24)
                .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.primary.opacity(0.07)))
                .shadow(color: .black.opacity(0.05), radius: 24, y: 8)
                .padding(.top, 34)

                Button {
                    store.usePreview()
                } label: {
                    Label("先看看：进入界面预览", systemImage: "sparkles")
                        .font(.subheadline.weight(.medium))
                }
                .foregroundStyle(AppTheme.accent)
                .padding(.top, 24)
                .accessibilityIdentifier("preview-button")

                Text("密码仅用于本次登录；会话凭证保存在系统钥匙串中。")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 22)
            }
            .frame(maxWidth: 460)
            .padding(.horizontal, 24)
            .padding(.vertical, 40)
            .frame(maxWidth: .infinity, minHeight: 700)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .scrollDismissesKeyboard(.interactively)
        .onAppear { focusedField = activeServer.isEmpty ? .server : .account }
        .onChange(of: connectionMode) { _, _ in focusedField = .server }
        .onChange(of: store.requiresOTP) { _, required in
            if required { focusedField = .otp }
        }
        .alert("无法继续", isPresented: $store.showError) {
            Button("好", role: .cancel) {}
        } message: {
            Text(store.errorMessage ?? "请稍后重试。")
        }
    }

    private func field(title: String, prompt: String, text: Binding<String>, field: Field) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            TextField(prompt, text: text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focusedField, equals: field)
                .submitLabel(.next)
                .onSubmit(moveNext)
                .padding(.horizontal, 14)
                .frame(height: 48)
                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func moveNext() {
        switch focusedField {
        case .server: focusedField = .account
        case .account: focusedField = .password
        default: break
        }
    }

    private func login() {
        guard !store.isLoggingIn else { return }
        focusedField = nil
        UserDefaults.standard.set(server, forKey: "last-server")
        UserDefaults.standard.set(quickConnectID, forKey: "quickconnect-id")
        Task {
            await store.login(
                server: activeServer,
                useHTTPS: useHTTPS,
                quickConnect: connectionMode == .quickConnect,
                account: account,
                password: password,
                otp: otp,
                rememberDevice: rememberDevice
            )
        }
    }
}
