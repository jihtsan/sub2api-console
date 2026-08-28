import Sub2APIKit
import SwiftUI

struct SettingsView: View {
  @ObservedObject var store: MonitorStore
  @StateObject private var launchAtLogin = LaunchAtLoginController()

  var body: some View {
    TabView {
      ConnectionSettingsView(store: store)
        .tabItem {
          Label("连接", systemImage: "network")
        }

      MonitoringSettingsView(store: store, launchAtLogin: launchAtLogin)
        .tabItem {
          Label("监控", systemImage: "speedometer")
        }

      AboutView()
        .tabItem {
          Label("关于", systemImage: "info.circle")
        }
    }
    .frame(width: 520, height: 420)
    .onAppear { store.start() }
  }
}

private struct ConnectionSettingsView: View {
  @ObservedObject var store: MonitorStore
  @ObservedObject private var settings: SettingsStore

  @State private var serverAddress: String
  @State private var email: String
  @State private var authenticationMode: AuthenticationMode
  @State private var password = ""
  @State private var apiKey = ""
  @State private var adminAPIKey = ""
  @State private var twoFactorCode = ""

  init(store: MonitorStore) {
    self.store = store
    settings = store.settings
    _serverAddress = State(initialValue: store.settings.serverAddress)
    _email = State(initialValue: store.settings.email)
    _authenticationMode = State(initialValue: store.settings.authenticationMode)
  }

  var body: some View {
    Form {
      Section("服务器") {
        TextField("地址", text: $serverAddress, prompt: Text("https://sub2api.example.com"))
          .textContentType(.URL)

        if isInsecureRemoteHTTP {
          Label("HTTP 连接不会加密凭据", systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(.orange)
          Toggle("允许不安全 HTTP", isOn: $settings.allowInsecureHTTP)
        } else if isInsecureHTTP {
          Label("本机 HTTP", systemImage: "desktopcomputer")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }

      Section("认证") {
        Picker("方式", selection: $authenticationMode) {
          Text("普通 Key").tag(AuthenticationMode.apiKey)
          Text("管理员 Key").tag(AuthenticationMode.adminAPIKey)
          Text("账户").tag(AuthenticationMode.account)
        }
        .pickerStyle(.segmented)
        .onChange(of: authenticationMode) { _, _ in
          store.cancelPendingLogin()
          password = ""
          apiKey = ""
          adminAPIKey = ""
          twoFactorCode = ""
        }

        switch authenticationMode {
        case .account:
          TextField("邮箱", text: $email)
            .textContentType(.emailAddress)
          SecureField("密码", text: $password)
            .textContentType(.password)

          if store.pendingTwoFactorEmail != nil {
            SecureField(
              "两步验证码",
              text: $twoFactorCode,
              prompt: Text(store.pendingTwoFactorEmail ?? "6 位验证码")
            )
            .textContentType(.oneTimeCode)
            .onChange(of: twoFactorCode) { _, value in
              twoFactorCode = String(value.filter(\.isNumber).prefix(6))
            }
          }
        case .apiKey:
          SecureField("普通 API Key", text: $apiKey, prompt: Text("sk-..."))
            .textContentType(.password)
        case .adminAPIKey:
          SecureField("管理员 API Key", text: $adminAPIKey, prompt: Text("admin-..."))
            .textContentType(.password)

          Label(
            "此密钥拥有完整的管理员权限，请妥善保管。",
            systemImage: "exclamationmark.triangle.fill"
          )
          .font(.caption)
          .foregroundStyle(.orange)
          .fixedSize(horizontal: false, vertical: true)
        }
      }

      Section {
        HStack {
          connectionStatus
          Spacer()

          if store.isConfigured {
            Button("断开连接", role: .destructive) {
              Task { await store.disconnect() }
            }
          }

          Button {
            connect()
          } label: {
            if store.state == .connecting {
              ProgressView()
                .controlSize(.small)
            } else {
              Label(connectButtonTitle, systemImage: "link")
            }
          }
          .buttonStyle(.borderedProminent)
          .disabled(!canConnect || store.state == .connecting)
        }
      }
    }
    .formStyle(.grouped)
    .padding(.top, 8)
  }

  @ViewBuilder
  private var connectionStatus: some View {
    switch store.state {
    case .failed(let message):
      Label(message, systemImage: "exclamationmark.triangle.fill")
        .foregroundStyle(.red)
        .font(.caption)
        .lineLimit(2)
    default:
      Label(store.statusLabel, systemImage: store.statusSymbol)
        .foregroundStyle(store.state == .connected ? Color.green : Color.secondary)
        .font(.caption)
    }
  }

  private var connectButtonTitle: String {
    store.pendingTwoFactorEmail == nil ? "连接" : "验证"
  }

  private var canConnect: Bool {
    guard !serverAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return false
    }
    guard !isInsecureRemoteHTTP || settings.allowInsecureHTTP else { return false }
    if authenticationMode == .account, store.pendingTwoFactorEmail != nil {
      return twoFactorCode.count == 6
    }
    switch authenticationMode {
    case .account:
      return !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty
    case .apiKey:
      return !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    case .adminAPIKey:
      return !adminAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
  }

  private var isInsecureHTTP: Bool {
    guard let endpoint = try? ServerEndpoint(serverAddress) else { return false }
    return !endpoint.isSecure
  }

  private var isInsecureRemoteHTTP: Bool {
    guard let endpoint = try? ServerEndpoint(serverAddress) else { return false }
    return !endpoint.isSecure && !endpoint.isLoopback
  }

  private func connect() {
    Task {
      if authenticationMode == .account, store.pendingTwoFactorEmail != nil {
        await store.completeTwoFactor(
          code: twoFactorCode,
          serverAddress: serverAddress,
          email: email
        )
        if store.state == .connected {
          password = ""
          twoFactorCode = ""
        }
        return
      }

      switch authenticationMode {
      case .account:
        await store.connectWithAccount(
          serverAddress: serverAddress,
          email: email,
          password: password
        )
        if store.state == .connected {
          password = ""
        }
      case .apiKey:
        await store.connectWithAPIKey(
          serverAddress: serverAddress,
          apiKey: apiKey
        )
        if store.state == .connected {
          apiKey = ""
        }
      case .adminAPIKey:
        await store.connectWithAdminAPIKey(
          serverAddress: serverAddress,
          apiKey: adminAPIKey
        )
        if store.state == .connected {
          adminAPIKey = ""
        }
      }
    }
  }
}

private struct MonitoringSettingsView: View {
  @ObservedObject var store: MonitorStore
  @ObservedObject var launchAtLogin: LaunchAtLoginController
  @ObservedObject private var settings: SettingsStore

  init(store: MonitorStore, launchAtLogin: LaunchAtLoginController) {
    self.store = store
    self.launchAtLogin = launchAtLogin
    settings = store.settings
  }

  var body: some View {
    Form {
      Section("刷新") {
        Picker("频率", selection: $settings.refreshInterval) {
          ForEach(RefreshInterval.allCases) { interval in
            Text(DisplayFormat.refreshInterval(interval)).tag(interval)
          }
        }
        .onChange(of: settings.refreshInterval) { _, _ in
          store.restartPolling()
        }

        Picker("菜单栏显示", selection: $settings.menuBarMetric) {
          ForEach(MenuBarMetric.allCases) { metric in
            Text(DisplayFormat.metricName(metric)).tag(metric)
          }
        }
      }

      Section("系统") {
        Toggle(
          "登录时启动",
          isOn: Binding(
            get: { launchAtLogin.isEnabled },
            set: { launchAtLogin.setEnabled($0) }
          )
        )

        if let error = launchAtLogin.errorMessage {
          Text(error)
            .font(.caption)
            .foregroundStyle(.red)
        }
      }
    }
    .formStyle(.grouped)
    .padding(.top, 8)
  }
}

private struct AboutView: View {
  private var version: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版"
  }

  var body: some View {
    Form {
      Section {
        LabeledContent("应用", value: "Sub2API Monitor")
        LabeledContent("版本", value: version)
        LabeledContent("许可证", value: "MIT")
      }

      Section("链接") {
        Link(destination: URL(string: "https://github.com/Wei-Shaw/sub2api")!) {
          Label("Sub2API", systemImage: "arrow.up.right.square")
        }
        Link(destination: URL(string: "https://github.com/jihtsan/sub2api-console")!) {
          Label("源代码", systemImage: "chevron.left.forwardslash.chevron.right")
        }
      }
    }
    .formStyle(.grouped)
    .padding(.top, 8)
  }
}
