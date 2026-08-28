import Combine
import Foundation
import Sub2APIKit

enum ConnectionState: Equatable {
  case unconfigured
  case connecting
  case connected
  case failed(String)
}

enum AdminAccountAction: Equatable {
  case queryResetCredits(Int64)
  case resetOpenAIQuota(Int64)

  var accountID: Int64 {
    switch self {
    case .queryResetCredits(let accountID), .resetOpenAIQuota(let accountID): accountID
    }
  }
}

@MainActor
final class MonitorStore: ObservableObject {
  @Published private(set) var state: ConnectionState = .unconfigured
  @Published private(set) var snapshot: MonitorSnapshot?
  @Published private(set) var isRefreshing = false
  @Published private(set) var pendingTwoFactorEmail: String?
  @Published private(set) var accountAction: AdminAccountAction?
  @Published private(set) var accountActionError: String?
  @Published private(set) var openAIQuotaByAccountID: [Int64: OpenAIQuotaUsage] = [:]
  @Published private(set) var openAIQuotaErrorByAccountID: [Int64: String] = [:]

  let settings: SettingsStore

  private let credentialStore: any CredentialStoring
  private var client: Sub2APIClient?
  private var activeMode: AuthenticationMode?
  private var pollingTask: Task<Void, Never>?
  private var pendingClient: Sub2APIClient?
  private var pendingTwoFactorToken: String?
  private var hasStarted = false
  private var isMenuPresented = false
  private var consecutiveFailures = 0
  private var retryAfterSeconds: Int?

  init(
    settings: SettingsStore,
    credentialStore: any CredentialStoring = KeychainCredentialStore()
  ) {
    self.settings = settings
    self.credentialStore = credentialStore
  }

  deinit {
    pollingTask?.cancel()
  }

  func start() {
    guard !hasStarted else { return }
    hasStarted = true

    do {
      let hasCredentials: Bool
      switch settings.authenticationMode {
      case .apiKey:
        hasCredentials = try credentialStore.loadAPIKey() != nil
      case .adminAPIKey:
        hasCredentials = try credentialStore.loadAdminAPIKey() != nil
      case .account:
        hasCredentials = try credentialStore.loadSession() != nil
      }
      guard !settings.serverAddress.isEmpty, hasCredentials else {
        state = .unconfigured
        return
      }

      client = try makeClient(serverAddress: settings.serverAddress)
      activeMode = settings.authenticationMode
      restartPolling()
      Task { await refresh() }
    } catch {
      state = .failed(error.localizedDescription)
    }
  }

  func connectWithAccount(serverAddress: String, email: String, password: String) async {
    state = .connecting
    resetPendingAuthentication()

    do {
      let candidate = try makeClient(serverAddress: serverAddress)
      let result = try await candidate.login(email: email, password: password)
      switch result {
      case .authenticated:
        finishConnection(
          client: candidate,
          serverAddress: serverAddress,
          email: email,
          mode: .account
        )
        await refresh()
      case .requiresTwoFactor(let tempToken, let maskedEmail):
        pendingClient = candidate
        pendingTwoFactorToken = tempToken
        pendingTwoFactorEmail = maskedEmail ?? email
        state = .connecting
      }
    } catch {
      recordFailure(error)
    }
  }

  func completeTwoFactor(code: String, serverAddress: String, email: String) async {
    guard let candidate = pendingClient, let tempToken = pendingTwoFactorToken else {
      state = .failed("两步验证会话已失效，请重新登录。")
      return
    }

    state = .connecting
    do {
      _ = try await candidate.completeTwoFactor(tempToken: tempToken, code: code)
      resetPendingAuthentication()
      finishConnection(
        client: candidate,
        serverAddress: serverAddress,
        email: email,
        mode: .account
      )
      await refresh()
    } catch {
      recordFailure(error)
    }
  }

  func connectWithAPIKey(serverAddress: String, apiKey: String) async {
    state = .connecting
    resetPendingAuthentication()

    do {
      let candidate = try makeClient(serverAddress: serverAddress)
      let apiKeySnapshot = try await candidate.connectAPIKey(apiKey)
      finishConnection(
        client: candidate,
        serverAddress: serverAddress,
        email: "",
        mode: .apiKey
      )
      snapshot = .apiKey(apiKeySnapshot)
      state = .connected
      consecutiveFailures = 0
      retryAfterSeconds = nil
    } catch {
      recordFailure(error)
    }
  }

  func connectWithAdminAPIKey(serverAddress: String, apiKey: String) async {
    state = .connecting
    resetPendingAuthentication()

    do {
      let candidate = try makeClient(serverAddress: serverAddress)
      let adminSnapshot = try await candidate.connectAdminAPIKey(apiKey)
      finishConnection(
        client: candidate,
        serverAddress: serverAddress,
        email: "",
        mode: .adminAPIKey
      )
      snapshot = .adminAPIKey(adminSnapshot)
      state = .connected
      consecutiveFailures = 0
      retryAfterSeconds = nil
    } catch {
      recordFailure(error)
    }
  }

  func refresh() async {
    guard let client, let activeMode else {
      if state != .unconfigured {
        state = .failed("尚未建立服务器连接。")
      }
      return
    }
    guard !isRefreshing else { return }

    isRefreshing = true
    defer { isRefreshing = false }

    do {
      switch activeMode {
      case .apiKey:
        snapshot = .apiKey(try await client.fetchAPIKeySnapshot())
      case .adminAPIKey:
        snapshot = .adminAPIKey(try await client.fetchAdminAPIKeySnapshot())
      case .account:
        snapshot = .account(try await client.fetchAccountSnapshot())
      }
      state = .connected
      consecutiveFailures = 0
      retryAfterSeconds = nil
      accountActionError = nil
    } catch is CancellationError {
      return
    } catch {
      recordFailure(error)
    }
  }

  func disconnect() async {
    pollingTask?.cancel()
    pollingTask = nil
    do {
      if let client {
        try await client.clearCredentials()
      } else {
        try credentialStore.clearAll()
      }
    } catch {
      state = .failed(error.localizedDescription)
      return
    }

    client = nil
    activeMode = nil
    snapshot = nil
    accountAction = nil
    accountActionError = nil
    openAIQuotaByAccountID = [:]
    openAIQuotaErrorByAccountID = [:]
    resetPendingAuthentication()
    consecutiveFailures = 0
    retryAfterSeconds = nil
    state = .unconfigured
  }

  func restartPolling() {
    pollingTask?.cancel()
    guard client != nil else { return }

    pollingTask = Task { [weak self] in
      while !Task.isCancelled {
        guard let self else { return }
        let nanoseconds = UInt64(self.pollingDelaySeconds) * 1_000_000_000
        do {
          try await Task.sleep(nanoseconds: nanoseconds)
        } catch {
          return
        }
        await self.refresh()
      }
    }
  }

  func setMenuPresented(_ presented: Bool) {
    guard isMenuPresented != presented else { return }
    isMenuPresented = presented
    restartPolling()
    if presented, client != nil {
      Task { await refresh() }
    }
  }

  func refreshAfterWake() {
    guard client != nil else { return }
    Task { await refresh() }
  }

  func refreshOpenAIQuota(_ accountID: Int64) async {
    await performAccountAction(.queryResetCredits(accountID))
  }

  func resetOpenAIQuota(_ accountID: Int64) async {
    await performAccountAction(.resetOpenAIQuota(accountID))
  }

  func openAIQuota(for accountID: Int64) -> OpenAIQuotaUsage? {
    openAIQuotaByAccountID[accountID]
  }

  func openAIQuotaError(for accountID: Int64) -> String? {
    openAIQuotaErrorByAccountID[accountID]
  }

  func isAccountActionInProgress(_ accountID: Int64) -> Bool {
    accountAction?.accountID == accountID
  }

  func cancelPendingLogin() {
    guard pendingClient != nil else { return }
    resetPendingAuthentication()
    state = client == nil ? .unconfigured : .connected
  }

  var serverWebURL: URL? {
    client?.webBaseURL
  }

  var serverHost: String {
    serverWebURL?.host ?? (settings.serverAddress.isEmpty ? "Sub2API" : settings.serverAddress)
  }

  var isConfigured: Bool { client != nil }

  var statusLabel: String {
    switch state {
    case .unconfigured:
      return "未连接"
    case .connecting:
      return "连接中"
    case .failed:
      return "连接异常"
    case .connected:
      if case .apiKey(let apiKeySnapshot) = snapshot {
        let usage = apiKeySnapshot.usage
        guard usage.isOperational else { return apiKeyStatusName(usage.status) }
      }
      if let unhealthyAccounts = snapshot?.adminStats?.unhealthyAccounts,
        unhealthyAccounts > 0
      {
        return "\(unhealthyAccounts) 个账户异常"
      }
      return "在线"
    }
  }

  var statusSymbol: String {
    switch state {
    case .unconfigured:
      return "circle.dotted"
    case .connecting:
      return "arrow.triangle.2.circlepath"
    case .failed:
      return "exclamationmark.triangle.fill"
    case .connected:
      if case .apiKey(let apiKeySnapshot) = snapshot,
        !apiKeySnapshot.usage.isOperational
      {
        return "exclamationmark.circle.fill"
      }
      if let unhealthyAccounts = snapshot?.adminStats?.unhealthyAccounts,
        unhealthyAccounts > 0
      {
        return "exclamationmark.circle.fill"
      }
      return "checkmark.circle.fill"
    }
  }

  var menuBarText: String? {
    guard let snapshot else { return nil }
    switch settings.menuBarMetric {
    case .remaining:
      switch snapshot {
      case .apiKey(let value):
        return DisplayFormat.currencyOrUnlimited(value.usage.effectiveRemaining)
      case .adminAPIKey(let value):
        return adminAccountAvailability(value.stats)
      case .account(let value):
        return DisplayFormat.currency(value.user.balance)
      }
    case .todayCost:
      return DisplayFormat.currency(todayCost)
    case .todayRequests:
      return todayRequests.map(DisplayFormat.count)
    case .rpm:
      return rpm.map { "\(DisplayFormat.rate($0)) RPM" }
    case .health:
      return statusLabel
    case .statusOnly:
      return nil
    }
  }

  var isHealthy: Bool {
    guard state == .connected else { return false }
    if case .apiKey(let value) = snapshot {
      return value.usage.isOperational
    }
    if let adminStats = snapshot?.adminStats {
      return adminStats.unhealthyAccounts == 0
    }
    return true
  }

  private var todayCost: Double? {
    switch snapshot {
    case .apiKey(let value): value.usage.usage?.today?.actualCost
    case .adminAPIKey(let value): value.stats.todayActualCost
    case .account(let value): value.userStats.todayActualCost
    case nil: nil
    }
  }

  private var todayRequests: Int? {
    switch snapshot {
    case .apiKey(let value): value.usage.usage?.today?.requests
    case .adminAPIKey(let value): value.stats.todayRequests
    case .account(let value): value.userStats.todayRequests
    case nil: nil
    }
  }

  private var rpm: Double? {
    switch snapshot {
    case .apiKey(let value): value.usage.usage?.rpm
    case .adminAPIKey(let value): value.stats.rpm
    case .account(let value): value.adminStats?.rpm ?? value.userStats.rpm
    case nil: nil
    }
  }

  private var pollingDelaySeconds: Int {
    let configured = settings.refreshInterval.rawValue
    let base = isMenuPresented ? configured : max(configured, 300)
    let multiplier = 1 << min(consecutiveFailures, 4)
    let backedOff = min(base * multiplier, 1_800)
    return max(backedOff, retryAfterSeconds ?? 0)
  }

  private func makeClient(serverAddress: String) throws -> Sub2APIClient {
    try Sub2APIClient(
      serverAddress: serverAddress,
      credentialStore: credentialStore,
      allowInsecureHTTP: settings.allowInsecureHTTP
    )
  }

  private func finishConnection(
    client: Sub2APIClient,
    serverAddress: String,
    email: String,
    mode: AuthenticationMode
  ) {
    if activeMode != mode {
      snapshot = nil
    }
    accountAction = nil
    accountActionError = nil
    openAIQuotaByAccountID = [:]
    openAIQuotaErrorByAccountID = [:]
    self.client = client
    activeMode = mode
    settings.serverAddress = serverAddress.trimmingCharacters(in: .whitespacesAndNewlines)
    settings.email = email.trimmingCharacters(in: .whitespacesAndNewlines)
    settings.authenticationMode = mode
    state = .connected
    consecutiveFailures = 0
    retryAfterSeconds = nil
    restartPolling()
  }

  private func recordFailure(_ error: Error) {
    consecutiveFailures += 1
    if let sub2APIError = error as? Sub2APIError,
      case .rateLimited(let retryAfter) = sub2APIError
    {
      retryAfterSeconds = retryAfter
    } else {
      retryAfterSeconds = nil
    }
    state = .failed(error.localizedDescription)
  }

  private func resetPendingAuthentication() {
    pendingClient = nil
    pendingTwoFactorToken = nil
    pendingTwoFactorEmail = nil
  }

  private func apiKeyStatusName(_ status: String?) -> String {
    switch status?.lowercased() {
    case "expired": "已过期"
    case "quota_exhausted": "额度耗尽"
    case "disabled": "已停用"
    default: "不可用"
    }
  }

  private func adminAccountAvailability(_ stats: AdminDashboardStats) -> String? {
    guard let total = stats.totalAccounts else { return nil }
    let normal = stats.normalAccounts ?? max(total - stats.unhealthyAccounts, 0)
    return "\(normal)/\(total) 可用"
  }

  private func performAccountAction(_ action: AdminAccountAction) async {
    guard snapshot?.supportsAdminAccountList == true else {
      accountActionError = "当前连接没有管理员账号操作权限。"
      return
    }
    guard let account = snapshot?.adminAccounts.first(where: { $0.id == action.accountID }),
      account.account.isOpenAIOAuth,
      !account.account.isShadow
    else {
      accountActionError = "只有非影子 OpenAI OAuth 账号支持该操作。"
      return
    }
    if case .resetOpenAIQuota = action,
      openAIQuotaByAccountID[action.accountID]?.availableResetCount ?? 0 <= 0
    {
      accountActionError = "请先查询可用重置次数，且当前账号没有可用的重置次数。"
      return
    }
    guard accountAction == nil else { return }
    guard let client else {
      accountActionError = "尚未建立服务器连接。"
      return
    }

    accountAction = action
    accountActionError = nil
    defer { accountAction = nil }

    do {
      var resetWarningCode: String?
      switch action {
      case .queryResetCredits(let accountID):
        let result = try await client.refreshOpenAIQuota(accountID: accountID)
        openAIQuotaByAccountID[accountID] = result.usage
        openAIQuotaErrorByAccountID[accountID] = nil
      case .resetOpenAIQuota(let accountID):
        let result = try await client.resetOpenAIQuota(accountID: accountID)
        if result.cacheRefreshed, let quota = result.quota {
          openAIQuotaByAccountID[accountID] = quota
        } else {
          openAIQuotaByAccountID[accountID] = nil
        }
        openAIQuotaErrorByAccountID[accountID] = nil
        resetWarningCode = result.warningCode
      }
      await refresh()
      if let resetWarningCode {
        accountActionError = openAIResetWarningMessage(resetWarningCode)
      }
    } catch is CancellationError {
      return
    } catch {
      openAIQuotaErrorByAccountID[action.accountID] = error.localizedDescription
      accountActionError = "账号操作失败：\(error.localizedDescription)"
    }
  }

  private func openAIResetWarningMessage(_ code: String) -> String {
    switch code {
    case "reset_credit_cache_refresh_failed":
      return "重置已执行，但重置次数缓存刷新失败，请重新查询。"
    case "account_state_recovery_failed":
      return "重置已执行，但账号状态恢复失败，请检查账号状态。"
    case "account_state_refresh_failed":
      return "重置已执行，但账号状态刷新失败，请稍后刷新。"
    default:
      return "重置已执行，但服务器返回了部分同步警告：\(code)"
    }
  }
}
