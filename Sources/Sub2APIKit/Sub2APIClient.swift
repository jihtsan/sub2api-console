import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

public actor Sub2APIClient {
  public static let minimumSafeAccountVersion = ServerVersion(major: 0, minor: 1, patch: 172)
  public static let verifiedVersion = ServerVersion(major: 0, minor: 1, patch: 183)

  private let endpoint: ServerEndpoint
  private let credentialStore: any CredentialStoring
  private let session: URLSession
  private let decoder = JSONDecoder()
  private let encoder: JSONEncoder
  private var cachedPublicSettings: PublicSettings?

  public init(
    serverAddress: String,
    credentialStore: any CredentialStoring = KeychainCredentialStore(),
    session: URLSession = .shared,
    allowInsecureHTTP: Bool = false
  ) throws {
    let endpoint = try ServerEndpoint(serverAddress)
    guard endpoint.usesAcceptableTransport || allowInsecureHTTP else {
      throw Sub2APIError.insecureServerAddress
    }
    self.endpoint = endpoint
    self.credentialStore = credentialStore
    self.session = session

    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    self.encoder = encoder
  }

  public nonisolated var webBaseURL: URL { endpoint.webBaseURL }

  public func fetchPublicSettings(forceRefresh: Bool = false) async throws -> PublicSettings {
    if !forceRefresh, let cachedPublicSettings {
      return cachedPublicSettings
    }
    let settings: PublicSettings = try await panelRequest(
      path: "settings/public",
      method: "GET",
      body: nil,
      accessToken: nil
    )
    cachedPublicSettings = settings
    return settings
  }

  public func login(email: String, password: String) async throws -> LoginResult {
    struct LoginRequest: Encodable {
      let email: String
      let password: String
    }

    let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedEmail.isEmpty, !password.isEmpty else {
      throw Sub2APIError.missingCredentials
    }

    if let settings = try? await fetchPublicSettings() {
      try validateAccountLoginVersion(settings.version)
      if settings.turnstileEnabled == true || settings.tencentCaptchaEnabled == true
        || settings.aliyunCaptchaEnabled == true
      {
        throw Sub2APIError.captchaRequired
      }
    }

    let payload: AuthPayload = try await panelRequest(
      path: "auth/login",
      method: "POST",
      body: encoder.encode(LoginRequest(email: normalizedEmail, password: password)),
      accessToken: nil
    )
    return try persistAuthentication(payload)
  }

  public func completeTwoFactor(tempToken: String, code: String) async throws -> UserProfile {
    struct TwoFactorRequest: Encodable {
      let tempToken: String
      let totpCode: String
    }

    let payload: AuthPayload = try await panelRequest(
      path: "auth/login/2fa",
      method: "POST",
      body: encoder.encode(TwoFactorRequest(tempToken: tempToken, totpCode: code)),
      accessToken: nil
    )

    switch try persistAuthentication(payload) {
    case .authenticated(let user):
      return user
    case .requiresTwoFactor:
      throw Sub2APIError.invalidResponse
    }
  }

  public func connectAPIKey(_ rawAPIKey: String) async throws -> APIKeyMonitorSnapshot {
    let apiKey = rawAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !apiKey.isEmpty else { throw Sub2APIError.missingCredentials }

    let usage = try await requestAPIKeyUsage(apiKey: apiKey)
    try credentialStore.saveAPIKey(apiKey)
    try credentialStore.clearSession()
    try credentialStore.clearAdminAPIKey()
    return APIKeyMonitorSnapshot(
      usage: usage,
      publicSettings: await loadPublicSettingsBestEffort(),
      warning: compatibilityWarning()
    )
  }

  public func fetchAPIKeySnapshot() async throws -> APIKeyMonitorSnapshot {
    guard let apiKey = try credentialStore.loadAPIKey() else {
      throw Sub2APIError.missingCredentials
    }
    let usage = try await requestAPIKeyUsage(apiKey: apiKey)
    return APIKeyMonitorSnapshot(
      usage: usage,
      publicSettings: await loadPublicSettingsBestEffort(),
      warning: compatibilityWarning()
    )
  }

  public func connectAdminAPIKey(_ rawAPIKey: String) async throws -> AdminAPIKeyMonitorSnapshot {
    let apiKey = rawAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !apiKey.isEmpty else { throw Sub2APIError.missingCredentials }

    let stats = try await requestAdminDashboardStats(apiKey: apiKey)
    let accountResult = await loadAdminAccountSnapshots(apiKey: apiKey)
    try credentialStore.saveAdminAPIKey(apiKey)
    try credentialStore.clearSession()
    try credentialStore.clearAPIKey()
    return AdminAPIKeyMonitorSnapshot(
      stats: stats,
      adminAccounts: accountResult.accounts,
      publicSettings: await loadPublicSettingsBestEffort(),
      warning: combinedWarning(compatibilityWarning(), accountResult.warning)
    )
  }

  public func fetchAdminAPIKeySnapshot() async throws -> AdminAPIKeyMonitorSnapshot {
    guard let apiKey = try credentialStore.loadAdminAPIKey() else {
      throw Sub2APIError.missingCredentials
    }
    let stats = try await requestAdminDashboardStats(apiKey: apiKey)
    let accountResult = await loadAdminAccountSnapshots(apiKey: apiKey)
    return AdminAPIKeyMonitorSnapshot(
      stats: stats,
      adminAccounts: accountResult.accounts,
      publicSettings: await loadPublicSettingsBestEffort(),
      warning: combinedWarning(compatibilityWarning(), accountResult.warning)
    )
  }

  public func fetchAdminAPIKeyList() async throws -> AdminAPIKeyListSnapshot {
    let users = try await fetchAllAdminUsers()
    let usersByID = Dictionary(uniqueKeysWithValues: users.map { ($0.id, $0) })
    var metadata: [(key: AdminAPIKeyMetadata, owner: AdminUserSummary)] = []
    var seenKeyIDs = Set<Int64>()

    for user in users {
      try Task.checkCancellation()
      var page = try await requestAdminAPIKeyPage(userID: user.id, page: 1, pageSize: 100)
      let pages = page.pages

      for key in page.items where seenKeyIDs.insert(key.id).inserted {
        metadata.append((key: key, owner: usersByID[key.userID] ?? user))
      }

      if pages > 1 {
        for pageNumber in 2...pages {
          try Task.checkCancellation()
          page = try await requestAdminAPIKeyPage(
            userID: user.id,
            page: pageNumber,
            pageSize: 100
          )
          for key in page.items where seenKeyIDs.insert(key.id).inserted {
            metadata.append((key: key, owner: usersByID[key.userID] ?? user))
          }
        }
      }
    }

    guard !metadata.isEmpty else {
      return AdminAPIKeyListSnapshot(items: [], warning: nil)
    }

    var todayRequestsByKeyID: [Int64: Int] = [:]
    var warning: String?
    do {
      let usage = try await requestAdminAPIKeyUsageTrend(limit: metadata.count)
      for point in usage.trend {
        todayRequestsByKeyID[point.apiKeyID, default: 0] += max(point.requests ?? 0, 0)
      }
    } catch {
      warning = "今日调用量暂不可用：\(error.localizedDescription)"
    }

    let items = metadata.map { entry in
      AdminAPIKeyListItem(
        metadata: entry.key,
        owner: entry.owner,
        todayRequests: warning == nil ? todayRequestsByKeyID[entry.key.id, default: 0] : nil
      )
    }
    return AdminAPIKeyListSnapshot(items: items, warning: warning)
  }

  public func fetchAccountSnapshot() async throws -> AccountMonitorSnapshot {
    let user: UserProfile = try await authorizedPanelRequest(path: "auth/me")
    let userStats: UserDashboardStats = try await authorizedPanelRequest(
      path: "usage/dashboard/stats",
      queryItems: [URLQueryItem(name: "timezone", value: TimeZone.current.identifier)]
    )

    var adminStats: AdminDashboardStats?
    var adminAccounts: [AdminAccountSnapshot] = []
    var warnings: [String] = []
    if user.isAdmin {
      do {
        adminStats = try await authorizedPanelRequest(path: "admin/dashboard/stats")
      } catch {
        warnings.append("管理员统计暂不可用：\(error.localizedDescription)")
      }

      let accountResult = await loadAdminAccountSnapshots(apiKey: nil)
      adminAccounts = accountResult.accounts
      if let warning = accountResult.warning {
        warnings.append(warning)
      }
    }

    let publicSettings = await loadPublicSettingsBestEffort()
    if let compatibilityWarning = compatibilityWarning() {
      warnings.append(compatibilityWarning)
    }
    return AccountMonitorSnapshot(
      user: user,
      userStats: userStats,
      adminStats: adminStats,
      adminAccounts: adminAccounts,
      publicSettings: publicSettings,
      warning: warnings.isEmpty ? nil : warnings.joined(separator: "\n")
    )
  }

  public func refreshOpenAIQuota(accountID: Int64) async throws -> OpenAIQuotaRefreshResult {
    try await requestAdminAuthorized(
      path: "admin/openai/accounts/\(accountID)/quota/refresh",
      method: "POST",
      body: nil,
      timeoutInterval: 60
    )
  }

  public func resetOpenAIQuota(accountID: Int64) async throws -> OpenAIQuotaResetResult {
    try await requestAdminAuthorized(
      path: "admin/openai/accounts/\(accountID)/reset-quota",
      method: "POST",
      body: nil,
      timeoutInterval: 90
    )
  }

  public func clearCredentials() throws {
    try credentialStore.clearAll()
  }

  private func requestAPIKeyUsage(apiKey: String) async throws -> APIKeyUsage {
    let queryItems = [
      URLQueryItem(name: "days", value: "7"),
      URLQueryItem(name: "timezone", value: TimeZone.current.identifier),
    ]
    var request = URLRequest(url: try endpoint.gatewayURL(path: "usage", queryItems: queryItems))
    configure(&request, method: "GET", body: nil, bearerToken: apiKey)

    let (data, response) = try await perform(request)
    guard (200..<300).contains(response.statusCode) else {
      throw mapHTTPError(response: response, data: data, authenticationLabel: "API Key")
    }

    do {
      let usage = try decoder.decode(APIKeyUsage.self, from: data)
      guard usage.mode != nil else { throw Sub2APIError.invalidResponse }
      return usage
    } catch let error as Sub2APIError {
      throw error
    } catch {
      throw Sub2APIError.invalidResponse
    }
  }

  private func loadAdminAccountSnapshots(apiKey: String?) async -> (
    accounts: [AdminAccountSnapshot],
    warning: String?
  ) {
    do {
      return (try await fetchAdminAccountSnapshots(apiKey: apiKey), nil)
    } catch {
      return ([], "账号列表暂不可用：\(error.localizedDescription)")
    }
  }

  private func fetchAllAdminUsers() async throws -> [AdminUserSummary] {
    let pageSize = 100
    var page = try await requestAdminUserPage(page: 1, pageSize: pageSize)
    var users = page.items

    if page.pages > 1 {
      for pageNumber in 2...page.pages {
        try Task.checkCancellation()
        page = try await requestAdminUserPage(page: pageNumber, pageSize: pageSize)
        users.append(contentsOf: page.items)
      }
    }
    return users
  }

  private func requestAdminUserPage(page: Int, pageSize: Int) async throws -> AdminUserPage {
    try await requestAdminAuthorized(
      path: "admin/users",
      method: "GET",
      body: nil,
      queryItems: [
        URLQueryItem(name: "page", value: String(page)),
        URLQueryItem(name: "page_size", value: String(pageSize)),
        URLQueryItem(name: "include_subscriptions", value: "false"),
      ],
      timeoutInterval: 30
    )
  }

  private func requestAdminAPIKeyPage(
    userID: Int64,
    page: Int,
    pageSize: Int
  ) async throws -> AdminAPIKeyPage {
    try await requestAdminAuthorized(
      path: "admin/users/\(userID)/api-keys",
      method: "GET",
      body: nil,
      queryItems: [
        URLQueryItem(name: "page", value: String(page)),
        URLQueryItem(name: "page_size", value: String(pageSize)),
      ],
      timeoutInterval: 30
    )
  }

  private func requestAdminAPIKeyUsageTrend(
    limit: Int
  ) async throws -> AdminAPIKeyUsageTrendResponse {
    let today = currentDateString()
    return try await requestAdminAuthorized(
      path: "admin/dashboard/api-keys-trend",
      method: "GET",
      body: nil,
      queryItems: [
        URLQueryItem(name: "start_date", value: today),
        URLQueryItem(name: "end_date", value: today),
        URLQueryItem(name: "granularity", value: "day"),
        URLQueryItem(name: "limit", value: String(max(limit, 1))),
        URLQueryItem(name: "timezone", value: TimeZone.current.identifier),
      ],
      timeoutInterval: 30
    )
  }

  private func currentDateString() -> String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone.current
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: Date())
  }

  private func fetchAdminAccountSnapshots(apiKey: String?) async throws -> [AdminAccountSnapshot] {
    let pageSize = 100
    var page = try await requestAdminAccountPage(page: 1, pageSize: pageSize, apiKey: apiKey)
    var accounts = page.items

    if page.pages > 1 {
      for pageNumber in 2...page.pages {
        try Task.checkCancellation()
        page = try await requestAdminAccountPage(
          page: pageNumber,
          pageSize: pageSize,
          apiKey: apiKey
        )
        accounts.append(contentsOf: page.items)
      }
    }

    guard !accounts.isEmpty else { return [] }

    let accountIDs = accounts
      .filter(supportsAdminAccountUsage)
      .map(\.id)
    guard !accountIDs.isEmpty else {
      return accounts.map { AdminAccountSnapshot(account: $0) }
    }

    let usageResult: AdminAccountUsageBatchResponse
    do {
      usageResult = try await requestAdminAccountUsage(
        accountIDs: accountIDs,
        apiKey: apiKey
      )
    } catch {
      return accounts.map {
        AdminAccountSnapshot(account: $0, usageError: error.localizedDescription)
      }
    }

    return accounts.map { account in
      let key = String(account.id)
      return AdminAccountSnapshot(
        account: account,
        usage: usageResult.usage[key],
        usageError: usageResult.errors[key]
      )
    }
  }

  private func supportsAdminAccountUsage(_ account: AdminAccount) -> Bool {
    switch (account.platform.lowercased(), account.type.lowercased()) {
    case ("anthropic", "oauth"), ("anthropic", "setup-token"):
      true
    case ("openai", "oauth"), ("gemini", _), ("antigravity", "oauth"), ("grok", "oauth"):
      true
    default:
      false
    }
  }

  private func requestAdminAccountPage(
    page: Int,
    pageSize: Int,
    apiKey: String?
  ) async throws -> AdminAccountPage {
    let queryItems = [
      URLQueryItem(name: "page", value: String(page)),
      URLQueryItem(name: "page_size", value: String(pageSize)),
      URLQueryItem(name: "lite", value: "true"),
      URLQueryItem(name: "sort_by", value: "name"),
      URLQueryItem(name: "sort_order", value: "asc"),
    ]

    if let apiKey {
      return try await adminAPIKeyRequest(
        path: "admin/accounts",
        method: "GET",
        body: nil,
        queryItems: queryItems,
        apiKey: apiKey
      )
    }
    return try await authorizedPanelRequest(
      path: "admin/accounts",
      method: "GET",
      body: nil,
      queryItems: queryItems
    )
  }

  private func requestAdminAccountUsage(
    accountIDs: [Int64],
    apiKey: String?
  ) async throws -> AdminAccountUsageBatchResponse {
    struct BatchUsageRequest: Encodable {
      let accountIDs: [Int64]
      let force: Bool
    }

    let body = try encoder.encode(BatchUsageRequest(accountIDs: accountIDs, force: false))
    if let apiKey {
      return try await adminAPIKeyRequest(
        path: "admin/accounts/usage/batch",
        method: "POST",
        body: body,
        queryItems: [],
        apiKey: apiKey
      )
    }
    return try await authorizedPanelRequest(
      path: "admin/accounts/usage/batch",
      method: "POST",
      body: body
    )
  }

  private func requestAdminAuthorized<Payload: Decodable & Sendable>(
    path: String,
    method: String,
    body: Data?,
    queryItems: [URLQueryItem] = [],
    timeoutInterval: TimeInterval
  ) async throws -> Payload {
    if let apiKey = try credentialStore.loadAdminAPIKey() {
      return try await adminAPIKeyRequest(
        path: path,
        method: method,
        body: body,
        queryItems: queryItems,
        apiKey: apiKey,
        timeoutInterval: timeoutInterval
      )
    }
    return try await authorizedPanelRequest(
      path: path,
      method: method,
      body: body,
      queryItems: queryItems,
      timeoutInterval: timeoutInterval
    )
  }

  private func adminAPIKeyRequest<Payload: Decodable & Sendable>(
    path: String,
    method: String,
    body: Data?,
    queryItems: [URLQueryItem],
    apiKey: String,
    timeoutInterval: TimeInterval = 30
  ) async throws -> Payload {
    var request = URLRequest(url: try endpoint.apiURL(path: path, queryItems: queryItems))
    configure(
      &request,
      method: method,
      body: body,
      bearerToken: nil,
      timeoutInterval: timeoutInterval
    )
    request.setValue(apiKey, forHTTPHeaderField: "x-api-key")

    let (data, response) = try await perform(request)
    guard (200..<300).contains(response.statusCode) else {
      throw mapHTTPError(response: response, data: data, authenticationLabel: "管理员 API Key")
    }

    let envelope: APIEnvelope<Payload>
    do {
      envelope = try decoder.decode(APIEnvelope<Payload>.self, from: data)
    } catch {
      throw Sub2APIError.invalidResponse
    }
    guard envelope.code == 0 else {
      throw Sub2APIError.api(
        code: envelope.code,
        message: envelope.message,
        reason: envelope.reason
      )
    }
    guard let payload = envelope.data else {
      throw Sub2APIError.invalidResponse
    }
    return payload
  }

  private func requestAdminDashboardStats(apiKey: String) async throws -> AdminDashboardStats {
    do {
      return try await adminAPIKeyRequest(
        path: "admin/dashboard/stats",
        method: "GET",
        body: nil,
        queryItems: [],
        apiKey: apiKey
      )
    } catch let error as Sub2APIError {
      if case .http(let status, _) = error, status == 423 {
        throw Sub2APIError.adminComplianceRequired
      }
      throw error
    }
  }

  private func persistAuthentication(_ payload: AuthPayload) throws -> LoginResult {
    if payload.requires2FA == true {
      guard let tempToken = payload.tempToken, !tempToken.isEmpty else {
        throw Sub2APIError.invalidResponse
      }
      return .requiresTwoFactor(tempToken: tempToken, maskedEmail: payload.userEmailMasked)
    }

    guard let accessToken = payload.accessToken,
      !accessToken.isEmpty,
      let user = payload.user
    else {
      throw Sub2APIError.invalidResponse
    }

    let expiresAt = payload.expiresIn.map { Date().addingTimeInterval(TimeInterval($0)) }
    try credentialStore.saveSession(
      StoredSession(
        accessToken: accessToken,
        refreshToken: payload.refreshToken,
        expiresAt: expiresAt
      ))
    try credentialStore.clearAPIKey()
    try credentialStore.clearAdminAPIKey()
    return .authenticated(user)
  }

  private func authorizedPanelRequest<Payload: Decodable & Sendable>(
    path: String,
    method: String = "GET",
    body: Data? = nil,
    queryItems: [URLQueryItem] = [],
    timeoutInterval: TimeInterval = 30
  ) async throws -> Payload {
    guard var storedSession = try credentialStore.loadSession() else {
      throw Sub2APIError.missingCredentials
    }

    if let expiresAt = storedSession.expiresAt,
      expiresAt.timeIntervalSinceNow <= 120,
      storedSession.refreshToken != nil
    {
      storedSession = try await refreshSession(storedSession)
    }

    do {
      return try await panelRequest(
        path: path,
        method: method,
        body: body,
        accessToken: storedSession.accessToken,
        queryItems: queryItems,
        timeoutInterval: timeoutInterval
      )
    } catch let error as Sub2APIError {
      guard case .unauthorized = error, storedSession.refreshToken != nil else {
        throw error
      }

      let refreshed = try await refreshSession(storedSession)
      return try await panelRequest(
        path: path,
        method: method,
        body: body,
        accessToken: refreshed.accessToken,
        queryItems: queryItems,
        timeoutInterval: timeoutInterval
      )
    }
  }

  private func refreshSession(_ session: StoredSession) async throws -> StoredSession {
    struct RefreshRequest: Encodable {
      let refreshToken: String
    }

    guard let refreshToken = session.refreshToken else {
      throw Sub2APIError.missingCredentials
    }

    let payload: RefreshTokenPayload = try await panelRequest(
      path: "auth/refresh",
      method: "POST",
      body: encoder.encode(RefreshRequest(refreshToken: refreshToken)),
      accessToken: nil
    )
    let refreshed = StoredSession(
      accessToken: payload.accessToken,
      refreshToken: payload.refreshToken,
      expiresAt: Date().addingTimeInterval(TimeInterval(payload.expiresIn))
    )
    try credentialStore.saveSession(refreshed)
    return refreshed
  }

  private func panelRequest<Payload: Decodable & Sendable>(
    path: String,
    method: String,
    body: Data?,
    accessToken: String?,
    queryItems: [URLQueryItem] = [],
    timeoutInterval: TimeInterval = 30
  ) async throws -> Payload {
    var request = URLRequest(url: try endpoint.apiURL(path: path, queryItems: queryItems))
    configure(
      &request,
      method: method,
      body: body,
      bearerToken: accessToken,
      timeoutInterval: timeoutInterval
    )

    let (data, response) = try await perform(request)
    guard (200..<300).contains(response.statusCode) else {
      throw mapHTTPError(response: response, data: data, authenticationLabel: "登录")
    }

    let envelope: APIEnvelope<Payload>
    do {
      envelope = try decoder.decode(APIEnvelope<Payload>.self, from: data)
    } catch {
      throw Sub2APIError.invalidResponse
    }

    guard envelope.code == 0 else {
      throw Sub2APIError.api(
        code: envelope.code, message: envelope.message, reason: envelope.reason)
    }
    guard let payload = envelope.data else {
      throw Sub2APIError.invalidResponse
    }
    return payload
  }

  private func configure(
    _ request: inout URLRequest,
    method: String,
    body: Data?,
    bearerToken: String?,
    timeoutInterval: TimeInterval = 30
  ) {
    request.httpMethod = method
    request.httpBody = body
    request.timeoutInterval = timeoutInterval
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("zh-CN", forHTTPHeaderField: "Accept-Language")
    request.setValue("Sub2APIConsole/0.1.0 (macOS)", forHTTPHeaderField: "User-Agent")
    if let bearerToken {
      request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
    }
  }

  private func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    do {
      let (data, response) = try await session.data(for: request)
      guard let httpResponse = response as? HTTPURLResponse else {
        throw Sub2APIError.invalidResponse
      }
      return (data, httpResponse)
    } catch let error as Sub2APIError {
      throw error
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      throw Sub2APIError.transport(error.localizedDescription)
    }
  }

  private func mapHTTPError(
    response: HTTPURLResponse,
    data: Data,
    authenticationLabel: String
  ) -> Sub2APIError {
    let message = responseMessage(from: data)
    if response.statusCode == 401 || response.statusCode == 403 {
      let fallback = "\(authenticationLabel)无效或已过期，请重新连接。"
      return .unauthorized(message.isEmpty ? fallback : message)
    }
    if response.statusCode == 429 {
      let retryAfter = response.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init)
      return .rateLimited(retryAfter: retryAfter)
    }
    return .http(
      status: response.statusCode,
      message: message.isEmpty
        ? HTTPURLResponse.localizedString(forStatusCode: response.statusCode) : message
    )
  }

  private func responseMessage(from data: Data) -> String {
    guard let object = try? JSONSerialization.jsonObject(with: data),
      let dictionary = object as? [String: Any]
    else {
      return ""
    }
    if let error = dictionary["error"] as? [String: Any],
      let message = error["message"] as? String
    {
      return message
    }
    if let error = dictionary["error"] as? String {
      return error
    }
    return dictionary["message"] as? String ?? ""
  }

  private func loadPublicSettingsBestEffort() async -> PublicSettings? {
    if let cachedPublicSettings { return cachedPublicSettings }
    return try? await fetchPublicSettings()
  }

  private func combinedWarning(_ first: String?, _ second: String?) -> String? {
    [first, second].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n").nilIfEmpty
  }

  private func validateAccountLoginVersion(_ versionString: String?) throws {
    guard let versionString, let version = ServerVersion(versionString) else { return }
    guard version >= Self.minimumSafeAccountVersion else {
      throw Sub2APIError.unsupportedServerVersion(versionString)
    }
  }

  private func compatibilityWarning() -> String? {
    guard let versionString = cachedPublicSettings?.version,
      let version = ServerVersion(versionString),
      version < Self.verifiedVersion
    else {
      return nil
    }
    return "服务器 \(versionString) 低于已验证的 v0.1.183，部分监控统计可能不准确。"
  }
}

private extension String {
  var nilIfEmpty: String? { isEmpty ? nil : self }
}
