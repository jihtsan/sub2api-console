import Foundation

public struct APIEnvelope<Payload: Decodable & Sendable>: Decodable, Sendable {
  public let code: Int
  public let message: String
  public let reason: String?
  public let data: Payload?
}

public struct PublicSettings: Decodable, Sendable, Equatable {
  public let version: String?
  public let siteName: String?
  public let turnstileEnabled: Bool?
  public let tencentCaptchaEnabled: Bool?
  public let totpEnabled: Bool?
  public let channelMonitorEnabled: Bool?
  public let channelMonitorMode: String?

  enum CodingKeys: String, CodingKey {
    case version
    case siteName = "site_name"
    case turnstileEnabled = "turnstile_enabled"
    case tencentCaptchaEnabled = "tencent_captcha_enabled"
    case totpEnabled = "totp_enabled"
    case channelMonitorEnabled = "channel_monitor_enabled"
    case channelMonitorMode = "channel_monitor_mode"
  }
}

public struct UserProfile: Decodable, Sendable, Equatable {
  public let id: Int64
  public let username: String
  public let email: String
  public let role: String
  public let balance: Double
  public let concurrency: Int?
  public let status: String?
  public let lastActiveAt: String?

  public var isAdmin: Bool { role == "admin" }

  enum CodingKeys: String, CodingKey {
    case id, username, email, role, balance, concurrency, status
    case lastActiveAt = "last_active_at"
  }
}

public struct AuthPayload: Decodable, Sendable {
  public let accessToken: String?
  public let refreshToken: String?
  public let expiresIn: Int?
  public let tokenType: String?
  public let user: UserProfile?
  public let requires2FA: Bool?
  public let tempToken: String?
  public let userEmailMasked: String?

  enum CodingKeys: String, CodingKey {
    case accessToken = "access_token"
    case refreshToken = "refresh_token"
    case expiresIn = "expires_in"
    case tokenType = "token_type"
    case user
    case requires2FA = "requires_2fa"
    case tempToken = "temp_token"
    case userEmailMasked = "user_email_masked"
  }
}

public struct RefreshTokenPayload: Decodable, Sendable {
  public let accessToken: String
  public let refreshToken: String
  public let expiresIn: Int
  public let tokenType: String

  enum CodingKeys: String, CodingKey {
    case accessToken = "access_token"
    case refreshToken = "refresh_token"
    case expiresIn = "expires_in"
    case tokenType = "token_type"
  }
}

public enum LoginResult: Sendable {
  case authenticated(UserProfile)
  case requiresTwoFactor(tempToken: String, maskedEmail: String?)
}

public struct UserDashboardStats: Decodable, Sendable, Equatable {
  public let totalAPIKeys: Int?
  public let activeAPIKeys: Int?
  public let totalRequests: Int?
  public let totalTokens: Int?
  public let totalActualCost: Double?
  public let todayRequests: Int?
  public let todayTokens: Int?
  public let todayActualCost: Double?
  public let averageDurationMs: Double?
  public let rpm: Double?
  public let tpm: Double?

  enum CodingKeys: String, CodingKey {
    case totalAPIKeys = "total_api_keys"
    case activeAPIKeys = "active_api_keys"
    case totalRequests = "total_requests"
    case totalTokens = "total_tokens"
    case totalActualCost = "total_actual_cost"
    case todayRequests = "today_requests"
    case todayTokens = "today_tokens"
    case todayActualCost = "today_actual_cost"
    case averageDurationMs = "average_duration_ms"
    case rpm, tpm
  }
}

public struct AdminDashboardStats: Decodable, Sendable, Equatable {
  public let totalUsers: Int?
  public let todayNewUsers: Int?
  public let activeUsers: Int?
  public let totalAPIKeys: Int?
  public let activeAPIKeys: Int?
  public let totalAccounts: Int?
  public let normalAccounts: Int?
  public let errorAccounts: Int?
  public let rateLimitAccounts: Int?
  public let overloadAccounts: Int?
  public let totalRequests: Int?
  public let totalTokens: Int?
  public let totalActualCost: Double?
  public let todayRequests: Int?
  public let todayTokens: Int?
  public let todayActualCost: Double?
  public let averageDurationMs: Double?
  public let uptime: Double?
  public let rpm: Double?
  public let tpm: Double?

  public var unhealthyAccounts: Int {
    (errorAccounts ?? 0) + (rateLimitAccounts ?? 0) + (overloadAccounts ?? 0)
  }

  enum CodingKeys: String, CodingKey {
    case totalUsers = "total_users"
    case todayNewUsers = "today_new_users"
    case activeUsers = "active_users"
    case totalAPIKeys = "total_api_keys"
    case activeAPIKeys = "active_api_keys"
    case totalAccounts = "total_accounts"
    case normalAccounts = "normal_accounts"
    case errorAccounts = "error_accounts"
    case rateLimitAccounts = "ratelimit_accounts"
    case overloadAccounts = "overload_accounts"
    case totalRequests = "total_requests"
    case totalTokens = "total_tokens"
    case totalActualCost = "total_actual_cost"
    case todayRequests = "today_requests"
    case todayTokens = "today_tokens"
    case todayActualCost = "today_actual_cost"
    case averageDurationMs = "average_duration_ms"
    case uptime, rpm, tpm
  }
}

public struct APIKeyUsage: Decodable, Sendable, Equatable {
  public let mode: String?
  public let isValid: Bool?
  public let status: String?
  public let planName: String?
  public let remaining: Double?
  public let unit: String?
  public let balance: Double?
  public let quota: APIKeyQuota?
  public let rateLimits: [APIKeyRateLimit]?
  public let expiresAt: String?
  public let daysUntilExpiry: Int?
  public let subscription: APIKeySubscription?
  public let usage: UsageSummary?
  public let dailyUsage: [APIKeyDailyUsage]?

  public var effectiveRemaining: Double? {
    quota?.remaining ?? remaining ?? balance
  }

  public var isOperational: Bool {
    guard isValid != false else { return false }
    switch status?.lowercased() {
    case "expired", "quota_exhausted", "disabled":
      return false
    default:
      return true
    }
  }

  enum CodingKeys: String, CodingKey {
    case mode, isValid, status, remaining, unit, balance, quota, subscription, usage
    case planName
    case rateLimits = "rate_limits"
    case expiresAt = "expires_at"
    case daysUntilExpiry = "days_until_expiry"
    case dailyUsage = "daily_usage"
  }
}

public struct APIKeyQuota: Decodable, Sendable, Equatable {
  public let limit: Double?
  public let used: Double?
  public let remaining: Double?
  public let unit: String?
}

public struct APIKeyRateLimit: Decodable, Sendable, Equatable, Identifiable {
  public let window: String
  public let limit: Double?
  public let used: Double?
  public let remaining: Double?
  public let windowStart: String?
  public let resetAt: String?

  public var id: String { window }

  enum CodingKeys: String, CodingKey {
    case window, limit, used, remaining
    case windowStart = "window_start"
    case resetAt = "reset_at"
  }
}

public struct APIKeySubscription: Decodable, Sendable, Equatable {
  public let dailyUsageUSD: Double?
  public let weeklyUsageUSD: Double?
  public let monthlyUsageUSD: Double?
  public let dailyLimitUSD: Double?
  public let weeklyLimitUSD: Double?
  public let monthlyLimitUSD: Double?
  public let weeklyWindowStart: String?
  public let expiresAt: String?

  enum CodingKeys: String, CodingKey {
    case dailyUsageUSD = "daily_usage_usd"
    case weeklyUsageUSD = "weekly_usage_usd"
    case monthlyUsageUSD = "monthly_usage_usd"
    case dailyLimitUSD = "daily_limit_usd"
    case weeklyLimitUSD = "weekly_limit_usd"
    case monthlyLimitUSD = "monthly_limit_usd"
    case weeklyWindowStart = "weekly_window_start"
    case expiresAt = "expires_at"
  }
}

public struct UsageSummary: Decodable, Sendable, Equatable {
  public let today: UsagePeriod?
  public let total: UsagePeriod?
  public let averageDurationMs: Double?
  public let rpm: Double?
  public let tpm: Double?

  enum CodingKeys: String, CodingKey {
    case today, total, rpm, tpm
    case averageDurationMs = "average_duration_ms"
  }
}

public struct UsagePeriod: Decodable, Sendable, Equatable {
  public let requests: Int?
  public let inputTokens: Int?
  public let outputTokens: Int?
  public let cacheCreationTokens: Int?
  public let cacheReadTokens: Int?
  public let totalTokens: Int?
  public let cost: Double?
  public let actualCost: Double?

  enum CodingKeys: String, CodingKey {
    case requests, cost
    case inputTokens = "input_tokens"
    case outputTokens = "output_tokens"
    case cacheCreationTokens = "cache_creation_tokens"
    case cacheReadTokens = "cache_read_tokens"
    case totalTokens = "total_tokens"
    case actualCost = "actual_cost"
  }
}

public struct APIKeyDailyUsage: Decodable, Sendable, Equatable {
  public let date: String?
  public let requests: Int?
  public let totalTokens: Int?
  public let actualCost: Double?

  enum CodingKeys: String, CodingKey {
    case date, requests
    case totalTokens = "total_tokens"
    case actualCost = "actual_cost"
  }
}

public struct APIKeyMonitorSnapshot: Sendable, Equatable {
  public let usage: APIKeyUsage
  public let publicSettings: PublicSettings?
  public let warning: String?
  public let fetchedAt: Date

  public init(
    usage: APIKeyUsage,
    publicSettings: PublicSettings?,
    warning: String?,
    fetchedAt: Date = Date()
  ) {
    self.usage = usage
    self.publicSettings = publicSettings
    self.warning = warning
    self.fetchedAt = fetchedAt
  }
}

public struct AccountMonitorSnapshot: Sendable, Equatable {
  public let user: UserProfile
  public let userStats: UserDashboardStats
  public let adminStats: AdminDashboardStats?
  public let publicSettings: PublicSettings?
  public let warning: String?
  public let fetchedAt: Date

  public init(
    user: UserProfile,
    userStats: UserDashboardStats,
    adminStats: AdminDashboardStats?,
    publicSettings: PublicSettings?,
    warning: String?,
    fetchedAt: Date = Date()
  ) {
    self.user = user
    self.userStats = userStats
    self.adminStats = adminStats
    self.publicSettings = publicSettings
    self.warning = warning
    self.fetchedAt = fetchedAt
  }
}

public enum MonitorSnapshot: Sendable, Equatable {
  case apiKey(APIKeyMonitorSnapshot)
  case account(AccountMonitorSnapshot)

  public var fetchedAt: Date {
    switch self {
    case .apiKey(let snapshot): snapshot.fetchedAt
    case .account(let snapshot): snapshot.fetchedAt
    }
  }

  public var warning: String? {
    switch self {
    case .apiKey(let snapshot): snapshot.warning
    case .account(let snapshot): snapshot.warning
    }
  }

  public var serverVersion: String? {
    switch self {
    case .apiKey(let snapshot): snapshot.publicSettings?.version
    case .account(let snapshot): snapshot.publicSettings?.version
    }
  }

  public var displayName: String {
    switch self {
    case .apiKey(let snapshot):
      return snapshot.usage.planName ?? "API Key"
    case .account(let snapshot):
      return snapshot.user.username
    }
  }

  public var remaining: Double? {
    switch self {
    case .apiKey(let snapshot):
      return snapshot.usage.effectiveRemaining
    case .account(let snapshot):
      return snapshot.user.balance
    }
  }

  public var todayCost: Double? {
    switch self {
    case .apiKey(let snapshot):
      return snapshot.usage.usage?.today?.actualCost
    case .account(let snapshot):
      return snapshot.userStats.todayActualCost
    }
  }

  public var todayRequests: Int? {
    switch self {
    case .apiKey(let snapshot):
      return snapshot.usage.usage?.today?.requests
    case .account(let snapshot):
      return snapshot.userStats.todayRequests
    }
  }

  public var rpm: Double? {
    switch self {
    case .apiKey(let snapshot):
      return snapshot.usage.usage?.rpm
    case .account(let snapshot):
      return snapshot.adminStats?.rpm ?? snapshot.userStats.rpm
    }
  }

  public var tpm: Double? {
    switch self {
    case .apiKey(let snapshot):
      return snapshot.usage.usage?.tpm
    case .account(let snapshot):
      return snapshot.adminStats?.tpm ?? snapshot.userStats.tpm
    }
  }

  public var averageDurationMs: Double? {
    switch self {
    case .apiKey(let snapshot):
      return snapshot.usage.usage?.averageDurationMs
    case .account(let snapshot):
      return snapshot.adminStats?.averageDurationMs ?? snapshot.userStats.averageDurationMs
    }
  }

  public var adminStats: AdminDashboardStats? {
    guard case .account(let snapshot) = self else { return nil }
    return snapshot.adminStats
  }

  public var isAdmin: Bool {
    guard case .account(let snapshot) = self else { return false }
    return snapshot.user.isAdmin
  }

  public var isAPIKey: Bool {
    if case .apiKey = self { return true }
    return false
  }
}

public enum AuthenticationMode: String, CaseIterable, Codable, Sendable, Identifiable {
  case apiKey
  case account

  public var id: String { rawValue }
}

public enum RefreshInterval: Int, CaseIterable, Codable, Sendable, Identifiable {
  case oneMinute = 60
  case fiveMinutes = 300
  case fifteenMinutes = 900
  case thirtyMinutes = 1_800

  public var id: Int { rawValue }
}

public enum MenuBarMetric: String, CaseIterable, Codable, Sendable, Identifiable {
  case remaining
  case todayCost
  case todayRequests
  case rpm
  case health
  case statusOnly

  public var id: String { rawValue }
}

public struct StoredSession: Codable, Sendable, Equatable {
  public let accessToken: String
  public let refreshToken: String?
  public let expiresAt: Date?

  public init(accessToken: String, refreshToken: String? = nil, expiresAt: Date? = nil) {
    self.accessToken = accessToken
    self.refreshToken = refreshToken
    self.expiresAt = expiresAt
  }
}

public struct ServerVersion: Sendable, Equatable, Comparable, CustomStringConvertible {
  public let major: Int
  public let minor: Int
  public let patch: Int

  public init(major: Int, minor: Int, patch: Int) {
    self.major = major
    self.minor = minor
    self.patch = patch
  }

  public init?(_ rawValue: String) {
    let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    let withoutPrefix = trimmed.hasPrefix("v") ? String(trimmed.dropFirst()) : trimmed
    let core = withoutPrefix.split(whereSeparator: { $0 == "-" || $0 == "+" }).first ?? ""
    let parts = core.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count >= 3,
      let major = Int(parts[0]),
      let minor = Int(parts[1]),
      let patch = Int(parts[2])
    else {
      return nil
    }
    self.init(major: major, minor: minor, patch: patch)
  }

  public static func < (lhs: ServerVersion, rhs: ServerVersion) -> Bool {
    if lhs.major != rhs.major { return lhs.major < rhs.major }
    if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
    return lhs.patch < rhs.patch
  }

  public var description: String { "v\(major).\(minor).\(patch)" }
}

public enum Sub2APIError: Error, LocalizedError, Sendable, Equatable {
  case invalidServerAddress
  case insecureCredentialsInURL
  case insecureServerAddress
  case missingCredentials
  case invalidResponse
  case unauthorized(String)
  case captchaRequired
  case unsupportedServerVersion(String)
  case rateLimited(retryAfter: Int?)
  case api(code: Int, message: String, reason: String?)
  case http(status: Int, message: String)
  case transport(String)
  case keychain(status: Int32)

  public var errorDescription: String? {
    switch self {
    case .invalidServerAddress:
      return "服务器地址无效，请填写完整的 http:// 或 https:// 地址。"
    case .insecureCredentialsInURL:
      return "服务器地址不能包含用户名或密码。"
    case .insecureServerAddress:
      return "远程服务器必须使用 HTTPS，或在设置中明确允许不安全 HTTP。"
    case .missingCredentials:
      return "尚未配置访问凭据。"
    case .invalidResponse:
      return "服务器返回了无法识别的数据。"
    case .unauthorized(let message):
      return message.isEmpty ? "凭据已失效，请重新连接。" : message
    case .captchaRequired:
      return "服务器已启用登录验证码，请改用 API Key 连接。"
    case .unsupportedServerVersion(let version):
      return "服务器 \(version) 存在已知认证安全风险，账户模式要求 v0.1.172 或更高版本。"
    case .rateLimited(let retryAfter):
      if let retryAfter {
        return "请求过于频繁，将在 \(retryAfter) 秒后重试。"
      }
      return "请求过于频繁，请稍后重试。"
    case .api(_, let message, _):
      return message
    case .http(let status, let message):
      return "HTTP \(status)：\(message)"
    case .transport(let message):
      return message
    case .keychain(let status):
      return "无法访问 Keychain（\(status)）。"
    }
  }
}
