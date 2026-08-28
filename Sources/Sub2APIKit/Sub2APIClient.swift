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
      if settings.turnstileEnabled == true || settings.tencentCaptchaEnabled == true {
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

  public func fetchAccountSnapshot() async throws -> AccountMonitorSnapshot {
    let user: UserProfile = try await authorizedPanelRequest(path: "auth/me")
    let userStats: UserDashboardStats = try await authorizedPanelRequest(
      path: "usage/dashboard/stats",
      queryItems: [URLQueryItem(name: "timezone", value: TimeZone.current.identifier)]
    )

    var adminStats: AdminDashboardStats?
    var warnings: [String] = []
    if user.isAdmin {
      do {
        adminStats = try await authorizedPanelRequest(path: "admin/dashboard/stats")
      } catch {
        warnings.append("管理员统计暂不可用：\(error.localizedDescription)")
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
      publicSettings: publicSettings,
      warning: warnings.isEmpty ? nil : warnings.joined(separator: "\n")
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
    return .authenticated(user)
  }

  private func authorizedPanelRequest<Payload: Decodable & Sendable>(
    path: String,
    queryItems: [URLQueryItem] = []
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
        method: "GET",
        body: nil,
        accessToken: storedSession.accessToken,
        queryItems: queryItems
      )
    } catch let error as Sub2APIError {
      guard case .unauthorized = error, storedSession.refreshToken != nil else {
        throw error
      }

      let refreshed = try await refreshSession(storedSession)
      return try await panelRequest(
        path: path,
        method: "GET",
        body: nil,
        accessToken: refreshed.accessToken,
        queryItems: queryItems
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
    queryItems: [URLQueryItem] = []
  ) async throws -> Payload {
    var request = URLRequest(url: try endpoint.apiURL(path: path, queryItems: queryItems))
    configure(&request, method: method, body: body, bearerToken: accessToken)

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
    bearerToken: String?
  ) {
    request.httpMethod = method
    request.httpBody = body
    request.timeoutInterval = 30
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
