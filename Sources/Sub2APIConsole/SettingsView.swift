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
    .frame(width: 560, height: 560)
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
  @State private var twoFactorCode = ""
  @State private var isPasswordVisible = false

  init(store: MonitorStore) {
    self.store = store
    settings = store.settings
    _serverAddress = State(initialValue: store.settings.serverAddress)
    _email = State(initialValue: store.settings.email)
    _authenticationMode = State(
      initialValue: store.settings.authenticationMode == .account ? .account : .apiKey
    )
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
          Text("API Key").tag(AuthenticationMode.apiKey)
          Text("账户").tag(AuthenticationMode.account)
        }
        .pickerStyle(.segmented)
        .onChange(of: authenticationMode) { _, _ in
          store.cancelPendingLogin()
          password = ""
          apiKey = ""
          twoFactorCode = ""
          isPasswordVisible = false
        }

        switch authenticationMode {
        case .account:
          TextField("邮箱", text: $email)
            .textContentType(.emailAddress)
          PasswordField(
            text: $password,
            isVisible: $isPasswordVisible
          )

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
        case .apiKey, .adminAPIKey:
          SecureField("API Key", text: $apiKey, prompt: Text("sk-... 或 admin-..."))
            .textContentType(.password)

          if let detectedAPIKeyMode {
            if detectedAPIKeyMode == .adminAPIKey {
              Label(
                "已识别为管理员 API Key。此密钥拥有完整的管理员权限，请妥善保管。",
                systemImage: "exclamationmark.triangle.fill"
              )
              .font(.caption)
              .foregroundStyle(.orange)
              .fixedSize(horizontal: false, vertical: true)
            } else {
              Label("已识别为普通 API Key", systemImage: "checkmark.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          } else if !trimmedAPIKey.isEmpty {
            Label(
              "无法识别 API Key，请使用 sk- 或 admin- 开头的 Key。",
              systemImage: "exclamationmark.triangle.fill"
            )
            .font(.caption)
            .foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
          }
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
    case .apiKey, .adminAPIKey:
      return detectedAPIKeyMode != nil
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
      case .apiKey, .adminAPIKey:
        guard let detectedAPIKeyMode else { return }
        switch detectedAPIKeyMode {
        case .apiKey:
          await store.connectWithAPIKey(
            serverAddress: serverAddress,
            apiKey: apiKey
          )
        case .adminAPIKey:
          await store.connectWithAdminAPIKey(
            serverAddress: serverAddress,
            apiKey: apiKey
          )
        case .account:
          return
        }
        if store.state == .connected {
          apiKey = ""
        }
      }
    }
  }

  private var trimmedAPIKey: String {
    apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private var detectedAPIKeyMode: AuthenticationMode? {
    AuthenticationMode.apiKeyMode(for: trimmedAPIKey)
  }
}

private struct PasswordField: View {
  @Binding var text: String
  @Binding var isVisible: Bool

  var body: some View {
    HStack(spacing: 6) {
      Group {
        if isVisible {
          TextField("密码", text: $text)
        } else {
          SecureField("密码", text: $text)
        }
      }
      .textContentType(.password)

      Button {
        isVisible.toggle()
      } label: {
        Image(systemName: isVisible ? "eye.slash" : "eye")
          .foregroundStyle(.secondary)
      }
      .buttonStyle(.plain)
      .accessibilityLabel(isVisible ? "隐藏密码" : "显示密码")
      .help(isVisible ? "隐藏密码" : "显示密码")
    }
  }
}

private enum DashboardMetricPreset: String, CaseIterable, Hashable, Identifiable {
  case summary
  case operations
  case traffic

  var id: String { rawValue }

  var title: String {
    switch self {
    case .summary: "运营概览"
    case .operations: "请求运维"
    case .traffic: "流量用量"
    }
  }

  var description: String {
    switch self {
    case .summary: "消费、请求、Token、平均响应和异常率"
    case .operations: "请求、响应时长、P95、异常率和成功率"
    case .traffic: "请求、Token、RPM、TPM 和消费"
    }
  }

  var metrics: [DashboardMetric] {
    switch self {
    case .summary:
      [.todayCost, .todayRequests, .todayTokens, .averageDuration, .errorRate]
    case .operations:
      [.todayRequests, .averageDuration, .p95Duration, .errorRate, .sla]
    case .traffic:
      [.todayRequests, .todayTokens, .rpm, .tpm, .todayCost]
    }
  }
}

private struct MonitoringSettingsView: View {
  @ObservedObject var store: MonitorStore
  @ObservedObject var launchAtLogin: LaunchAtLoginController
  @ObservedObject private var settings: SettingsStore
  @State private var selectedPreset: DashboardMetricPreset?

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

      Section("摘要卡片") {
        Picker("预设", selection: $selectedPreset) {
          ForEach(DashboardMetricPreset.allCases) { preset in
            Text(preset.title)
              .tag(preset as DashboardMetricPreset?)
          }
          Text("自定义")
            .tag(nil as DashboardMetricPreset?)
        }
        .onChange(of: selectedPreset) { _, preset in
          guard let preset else { return }
          settings.applyDashboardMetrics(preset.metrics)
        }

        Text(selectedPreset?.description ?? "按需选择要显示的指标")
          .font(.caption)
          .foregroundStyle(.secondary)

        HStack {
          Text("已选择")
          Spacer()
          Text("\(settings.dashboardMetrics.count) / \(SettingsStore.maxDashboardMetrics)")
            .monospacedDigit()
            .foregroundStyle(.secondary)
        }
        .font(.caption)

        ForEach(DashboardMetric.allCases) { metric in
          Toggle(
            isOn: Binding(
              get: { settings.dashboardMetrics.contains(metric) },
              set: { settings.setDashboardMetric(metric, enabled: $0) }
            )
          ) {
            HStack(spacing: 7) {
              Label(
                DisplayFormat.dashboardMetricName(metric),
                systemImage: dashboardMetricSymbol(metric)
              )
              Spacer(minLength: 8)
              if metric.requiresAdminOps {
                Text("管理员 Ops")
                  .font(.caption2)
                  .foregroundStyle(.secondary)
              }
            }
          }
          .disabled(
            !settings.dashboardMetrics.contains(metric)
              && settings.dashboardMetrics.count >= SettingsStore.maxDashboardMetrics
          )
        }

        Text("异常率、P95 和成功率需要管理员权限与服务端 Ops 监控；不支持时会显示为暂无数据。")
          .font(.caption2)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
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
    .onAppear { synchronizePreset() }
    .onChange(of: settings.dashboardMetrics) { _, _ in synchronizePreset() }
  }

  private func synchronizePreset() {
    selectedPreset = DashboardMetricPreset.allCases.first {
      $0.metrics == settings.dashboardMetrics
    }
  }

  private func dashboardMetricSymbol(_ metric: DashboardMetric) -> String {
    switch metric {
    case .todayCost: "arrow.up.right"
    case .todayRequests: "arrow.left.arrow.right"
    case .todayTokens: "number"
    case .averageDuration: "timer"
    case .p95Duration: "chart.line.uptrend.xyaxis"
    case .errorRate: "exclamationmark.triangle"
    case .sla: "checkmark.shield"
    case .rpm: "speedometer"
    case .tpm: "number"
    }
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
