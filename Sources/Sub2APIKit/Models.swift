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
  public let aliyunCaptchaEnabled: Bool?
  public let totpEnabled: Bool?
  public let channelMonitorEnabled: Bool?
  public let channelMonitorMode: String?

  enum CodingKeys: String, CodingKey {
    case version
    case siteName = "site_name"
    case turnstileEnabled = "turnstile_enabled"
    case tencentCaptchaEnabled = "tencent_captcha_enabled"
    case aliyunCaptchaEnabled = "aliyun_captcha_enabled"
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

/// A compact, read-only snapshot from the administrator Ops dashboard.
///
/// Ops monitoring is optional on the server, so every field is deliberately
/// optional. This lets older servers and disabled installations continue to
/// provide the regular dashboard summary.
public struct OpsDashboardSnapshot: Decodable, Sendable, Equatable {
  public let generatedAt: String?
  public let overview: OpsDashboardOverview?

  enum CodingKeys: String, CodingKey {
    case generatedAt = "generated_at"
    case overview
  }
}

public struct OpsDashboardOverview: Decodable, Sendable, Equatable {
  public let healthScore: Int?
  public let successCount: Int64?
  public let errorCountTotal: Int64?
  public let requestCountTotal: Int64?
  public let tokenConsumed: Int64?
  public let sla: Double?
  public let errorRate: Double?
  public let upstreamErrorRate: Double?
  public let qps: OpsRateSummary?
  public let tps: OpsRateSummary?
  public let duration: OpsPercentiles?
  public let ttft: OpsPercentiles?

  enum CodingKeys: String, CodingKey {
    case healthScore = "health_score"
    case successCount = "success_count"
    case errorCountTotal = "error_count_total"
    case requestCountTotal = "request_count_total"
    case tokenConsumed = "token_consumed"
    case sla
    case errorRate = "error_rate"
    case upstreamErrorRate = "upstream_error_rate"
    case qps, tps, duration, ttft
  }
}

public struct OpsRateSummary: Decodable, Sendable, Equatable {
  public let current: Double?
  public let peak: Double?
  public let average: Double?

  enum CodingKeys: String, CodingKey {
    case current, peak
    case average = "avg"
  }
}

public struct OpsPercentiles: Decodable, Sendable, Equatable {
  public let p50Ms: Int?
  public let p90Ms: Int?
  public let p95Ms: Int?
  public let p99Ms: Int?
  public let averageMs: Int?
  public let maxMs: Int?

  enum CodingKeys: String, CodingKey {
    case p50Ms = "p50_ms"
    case p90Ms = "p90_ms"
    case p95Ms = "p95_ms"
    case p99Ms = "p99_ms"
    case averageMs = "avg_ms"
    case maxMs = "max_ms"
  }
}

public struct AdminAccount: Decodable, Sendable, Equatable, Identifiable {
  public let id: Int64
  public let name: String
  public let platform: String
  public let type: String
  public let status: String?
  public let errorMessage: String?
  public let schedulable: Bool?
  public let rateLimitedAt: String?
  public let rateLimitResetAt: String?
  public let overloadUntil: String?
  public let tempUnschedulableUntil: String?
  public let tempUnschedulableReason: String?
  public let sessionWindowStatus: String?
  public let extra: AdminAccountExtra?
  public let currentConcurrency: Int?
  public let updatedAt: String?
  public let quotaWeeklyLimit: Double?
  public let quotaWeeklyUsed: Double?
  public let quotaWeeklyResetAt: String?
  public let parentAccountID: Int64?
  public let quotaDimension: String?

  public var rateLimitResetDate: Date? {
    parseISO8601Date(rateLimitResetAt)
  }

  public var isRateLimited: Bool {
    switch status?.lowercased() {
    case "rate_limited", "ratelimited":
      return true
    default:
      return rateLimitResetDate.map { $0 > Date() } ?? false
    }
  }

  public var isOverloaded: Bool {
    hasValue(overloadUntil) || status?.lowercased() == "overloaded"
  }

  public var isTemporarilyUnschedulable: Bool {
    hasValue(tempUnschedulableUntil) || hasValue(tempUnschedulableReason)
  }

  public var isOpenAIOAuth: Bool {
    platform.lowercased() == "openai" && type.lowercased() == "oauth"
  }

  public var isShadow: Bool {
    parentAccountID != nil || quotaDimension?.lowercased() == "spark"
  }

  enum CodingKeys: String, CodingKey {
    case id, name, platform, type, status, schedulable, extra
    case parentAccountID = "parent_account_id"
    case quotaDimension = "quota_dimension"
    case quotaWeeklyLimit = "quota_weekly_limit"
    case quotaWeeklyUsed = "quota_weekly_used"
    case quotaWeeklyResetAt = "quota_weekly_reset_at"
    case errorMessage = "error_message"
    case rateLimitedAt = "rate_limited_at"
    case rateLimitResetAt = "rate_limit_reset_at"
    case overloadUntil = "overload_until"
    case tempUnschedulableUntil = "temp_unschedulable_until"
    case tempUnschedulableReason = "temp_unschedulable_reason"
    case sessionWindowStatus = "session_window_status"
    case currentConcurrency = "current_concurrency"
    case updatedAt = "updated_at"
  }

  private func hasValue(_ value: String?) -> Bool {
    guard let value else { return false }
    return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private func parseISO8601Date(_ rawValue: String?) -> Date? {
    guard let rawValue, !rawValue.isEmpty else { return nil }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.date(from: rawValue)
      ?? {
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: rawValue)
      }()
  }
}

public struct AdminAccountExtra: Decodable, Sendable, Equatable {
  public let codex5hUsedPercent: Double?
  public let codex5hResetAfterSeconds: Double?
  public let codex5hResetAt: String?
  public let codex7dUsedPercent: Double?
  public let codex7dResetAfterSeconds: Double?
  public let codex7dResetAt: String?
  public let codexUsageUpdatedAt: String?

  enum CodingKeys: String, CodingKey {
    case codex5hUsedPercent = "codex_5h_used_percent"
    case codex5hResetAfterSeconds = "codex_5h_reset_after_seconds"
    case codex5hResetAt = "codex_5h_reset_at"
    case codex7dUsedPercent = "codex_7d_used_percent"
    case codex7dResetAfterSeconds = "codex_7d_reset_after_seconds"
    case codex7dResetAt = "codex_7d_reset_at"
    case codexUsageUpdatedAt = "codex_usage_updated_at"
  }
}

public struct AdminAccountUsageProgress: Decodable, Sendable, Equatable {
  public let utilization: Double?
  public let resetsAt: String?
  public let remainingSeconds: Double?

  enum CodingKeys: String, CodingKey {
    case utilization
    case resetsAt = "resets_at"
    case remainingSeconds = "remaining_seconds"
  }
}

public struct AdminAccountUsageInfo: Decodable, Sendable, Equatable {
  public let updatedAt: String?
  public let sevenDay: AdminAccountUsageProgress?
  public let errorCode: String?
  public let error: String?

  enum CodingKeys: String, CodingKey {
    case sevenDay = "seven_day"
    case updatedAt = "updated_at"
    case errorCode = "error_code"
    case error
  }
}

public struct AdminAccountPage: Decodable, Sendable, Equatable {
  public let items: [AdminAccount]
  public let total: Int
  public let page: Int
  public let pageSize: Int
  public let pages: Int

  enum CodingKeys: String, CodingKey {
    case items, total, page, pages
    case pageSize = "page_size"
  }
}

public struct AdminUserSummary: Decodable, Sendable, Equatable, Identifiable {
  public let id: Int64
  public let username: String?
  public let email: String?

  public var displayName: String {
    if let username = username?.trimmingCharacters(in: .whitespacesAndNewlines),
      !username.isEmpty
    {
      return username
    }
    if let email = email?.trimmingCharacters(in: .whitespacesAndNewlines), !email.isEmpty {
      return email
    }
    return "用户 \(id)"
  }

  enum CodingKeys: String, CodingKey {
    case id, username, email
  }
}

public struct AdminUserPage: Decodable, Sendable, Equatable {
  public let items: [AdminUserSummary]
  public let total: Int
  public let page: Int
  public let pageSize: Int
  public let pages: Int

  enum CodingKeys: String, CodingKey {
    case items, total, page, pages
    case pageSize = "page_size"
  }
}

public struct AdminAPIKeyGroup: Decodable, Sendable, Equatable {
  public let id: Int64
  public let name: String
}

/// Metadata for an administrator's API key. The secret `key` field is
/// deliberately not modeled so it cannot be rendered by the console.
public struct AdminAPIKeyMetadata: Decodable, Sendable, Equatable, Identifiable {
  public let id: Int64
  public let userID: Int64
  public let name: String
  public let groupID: Int64?
  public let status: String?
  public let group: AdminAPIKeyGroup?

  enum CodingKeys: String, CodingKey {
    case id, name, status, group
    case userID = "user_id"
    case groupID = "group_id"
  }
}

public struct AdminAPIKeyPage: Decodable, Sendable, Equatable {
  public let items: [AdminAPIKeyMetadata]
  public let total: Int
  public let page: Int
  public let pageSize: Int
  public let pages: Int

  enum CodingKeys: String, CodingKey {
    case items, total, page, pages
    case pageSize = "page_size"
  }
}

public struct AdminAPIKeyUsageTrendPoint: Decodable, Sendable, Equatable {
  public let date: String
  public let apiKeyID: Int64
  public let keyName: String?
  public let requests: Int?
  public let tokens: Int?

  enum CodingKeys: String, CodingKey {
    case date, keyName = "key_name", requests, tokens
    case apiKeyID = "api_key_id"
  }
}

public struct AdminAPIKeyUsageTrendResponse: Decodable, Sendable, Equatable {
  public let trend: [AdminAPIKeyUsageTrendPoint]
}

public struct AdminAPIKeyListItem: Sendable, Equatable, Identifiable {
  public let id: Int64
  public let name: String
  public let groupName: String
  public let ownerDisplayName: String
  public let status: String?
  public let todayRequests: Int?

  public var displayName: String {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? "未命名 API" : trimmed
  }

  public init(
    metadata: AdminAPIKeyMetadata,
    owner: AdminUserSummary,
    todayRequests: Int?
  ) {
    self.id = metadata.id
    self.name = metadata.name
    self.groupName = Self.groupName(for: metadata)
    self.ownerDisplayName = owner.displayName
    self.status = metadata.status
    self.todayRequests = todayRequests
  }

  private static func groupName(for metadata: AdminAPIKeyMetadata) -> String {
    if let name = metadata.group?.name.trimmingCharacters(in: .whitespacesAndNewlines),
      !name.isEmpty
    {
      return name
    }
    if let groupID = metadata.groupID {
      return "分组 \(groupID)"
    }
    return "未分组"
  }
}

public struct AdminAPIKeyListSnapshot: Sendable, Equatable {
  public let items: [AdminAPIKeyListItem]
  public let warning: String?
  public let fetchedAt: Date

  public init(
    items: [AdminAPIKeyListItem],
    warning: String?,
    fetchedAt: Date = Date()
  ) {
    self.items = items
    self.warning = warning
    self.fetchedAt = fetchedAt
  }
}

public struct AdminAccountUsageBatchResponse: Decodable, Sendable, Equatable {
  public let usage: [String: AdminAccountUsageInfo]
  public let errors: [String: String]
}

public struct OpenAIRateLimitWindow: Decodable, Sendable, Equatable {
  public let usedPercent: Double
  public let limitWindowSeconds: Double
  public let resetAfterSeconds: Double
  public let resetAt: Double

  enum CodingKeys: String, CodingKey {
    case usedPercent = "used_percent"
    case limitWindowSeconds = "limit_window_seconds"
    case resetAfterSeconds = "reset_after_seconds"
    case resetAt = "reset_at"
  }
}

public struct OpenAIRateLimit: Decodable, Sendable, Equatable {
  public let allowed: Bool
  public let limitReached: Bool
  public let primaryWindow: OpenAIRateLimitWindow?
  public let secondaryWindow: OpenAIRateLimitWindow?

  enum CodingKeys: String, CodingKey {
    case allowed
    case limitReached = "limit_reached"
    case primaryWindow = "primary_window"
    case secondaryWindow = "secondary_window"
  }
}

public struct OpenAIAdditionalRateLimit: Decodable, Sendable, Equatable {
  public let limitName: String
  public let meteredFeature: String
  public let rateLimit: OpenAIRateLimit?

  enum CodingKeys: String, CodingKey {
    case limitName = "limit_name"
    case meteredFeature = "metered_feature"
    case rateLimit = "rate_limit"
  }
}

public struct OpenAIRateLimitResetCreditDetail: Decodable, Sendable, Equatable {
  public let expiresAt: String?

  enum CodingKeys: String, CodingKey {
    case expiresAt = "expires_at"
  }
}

public struct OpenAIRateLimitResetCredits: Decodable, Sendable, Equatable {
  public let availableCount: Int
  public let credits: [OpenAIRateLimitResetCreditDetail]?

  enum CodingKeys: String, CodingKey {
    case availableCount = "available_count"
    case credits
  }
}

public struct OpenAIQuotaUsage: Decodable, Sendable, Equatable {
  public let userID: String?
  public let accountID: String?
  public let email: String?
  public let planType: String?
  public let rateLimit: OpenAIRateLimit?
  public let additionalRateLimits: [OpenAIAdditionalRateLimit]?
  public let rateLimitResetCredits: OpenAIRateLimitResetCredits?
  public let fetchedAt: Double

  public var availableResetCount: Int {
    max(0, rateLimitResetCredits?.availableCount ?? 0)
  }

  enum CodingKeys: String, CodingKey {
    case userID = "user_id"
    case accountID = "account_id"
    case email
    case planType = "plan_type"
    case rateLimit = "rate_limit"
    case additionalRateLimits = "additional_rate_limits"
    case rateLimitResetCredits = "rate_limit_reset_credits"
    case fetchedAt = "fetched_at"
  }
}

public struct OpenAIQuotaRefreshResult: Decodable, Sendable, Equatable {
  public let userID: String?
  public let accountID: String?
  public let email: String?
  public let planType: String?
  public let rateLimit: OpenAIRateLimit?
  public let additionalRateLimits: [OpenAIAdditionalRateLimit]?
  public let rateLimitResetCredits: OpenAIRateLimitResetCredits?
  public let fetchedAt: Double
  public let cachePersisted: Bool

  public var usage: OpenAIQuotaUsage {
    OpenAIQuotaUsage(
      userID: userID,
      accountID: accountID,
      email: email,
      planType: planType,
      rateLimit: rateLimit,
      additionalRateLimits: additionalRateLimits,
      rateLimitResetCredits: rateLimitResetCredits,
      fetchedAt: fetchedAt
    )
  }

  enum CodingKeys: String, CodingKey {
    case userID = "user_id"
    case accountID = "account_id"
    case email
    case planType = "plan_type"
    case rateLimit = "rate_limit"
    case additionalRateLimits = "additional_rate_limits"
    case rateLimitResetCredits = "rate_limit_reset_credits"
    case fetchedAt = "fetched_at"
    case cachePersisted = "cache_persisted"
  }
}

public struct OpenAIQuotaResetCredit: Decodable, Sendable, Equatable {
  public let id: String?
  public let resetType: String?
  public let status: String?
  public let grantedAt: String?
  public let expiresAt: String?
  public let redeemStartedAt: String?
  public let redeemedAt: String?

  enum CodingKeys: String, CodingKey {
    case id
    case resetType = "reset_type"
    case status
    case grantedAt = "granted_at"
    case expiresAt = "expires_at"
    case redeemStartedAt = "redeem_started_at"
    case redeemedAt = "redeemed_at"
  }
}

public struct OpenAIQuotaResetResult: Decodable, Sendable, Equatable {
  public let code: String
  public let credit: OpenAIQuotaResetCredit?
  public let windowsReset: Int
  public let quota: OpenAIQuotaUsage?
  public let account: AdminAccount?
  public let cacheRefreshed: Bool
  public let accountStateRecovered: Bool
  public let warningCode: String?

  enum CodingKeys: String, CodingKey {
    case code, credit
    case windowsReset = "windows_reset"
    case quota, account
    case cacheRefreshed = "cache_refreshed"
    case accountStateRecovered = "account_state_recovered"
    case warningCode = "warning_code"
  }
}

public struct AdminAccountSnapshot: Sendable, Equatable, Identifiable {
  public let account: AdminAccount
  public let usage: AdminAccountUsageInfo?
  public let usageError: String?

  public var id: Int64 { account.id }

  public var sevenDayUsagePercent: Double? {
    if let utilization = usage?.sevenDay?.utilization ?? account.extra?.codex7dUsedPercent {
      return utilization
    }
    guard let limit = account.quotaWeeklyLimit, limit > 0 else { return nil }
    return (account.quotaWeeklyUsed ?? 0) / limit * 100
  }

  public var sevenDayResetAt: String? {
    usage?.sevenDay?.resetsAt ?? account.extra?.codex7dResetAt ?? account.quotaWeeklyResetAt
  }

  public var sevenDayRemainingSeconds: Double? {
    usage?.sevenDay?.remainingSeconds ?? account.extra?.codex7dResetAfterSeconds
  }

  public init(
    account: AdminAccount,
    usage: AdminAccountUsageInfo? = nil,
    usageError: String? = nil
  ) {
    self.account = account
    self.usage = usage
    self.usageError = usageError
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

public struct AdminAPIKeyMonitorSnapshot: Sendable, Equatable {
  public let stats: AdminDashboardStats
  public let adminAccounts: [AdminAccountSnapshot]
  public let opsSnapshot: OpsDashboardSnapshot?
  public let publicSettings: PublicSettings?
  public let warning: String?
  public let fetchedAt: Date

  public init(
    stats: AdminDashboardStats,
    adminAccounts: [AdminAccountSnapshot] = [],
    opsSnapshot: OpsDashboardSnapshot? = nil,
    publicSettings: PublicSettings?,
    warning: String?,
    fetchedAt: Date = Date()
  ) {
    self.stats = stats
    self.adminAccounts = adminAccounts
    self.opsSnapshot = opsSnapshot
    self.publicSettings = publicSettings
    self.warning = warning
    self.fetchedAt = fetchedAt
  }
}

public struct AccountMonitorSnapshot: Sendable, Equatable {
  public let user: UserProfile
  public let userStats: UserDashboardStats
  public let adminStats: AdminDashboardStats?
  public let adminAccounts: [AdminAccountSnapshot]
  public let opsSnapshot: OpsDashboardSnapshot?
  public let publicSettings: PublicSettings?
  public let warning: String?
  public let fetchedAt: Date

  public init(
    user: UserProfile,
    userStats: UserDashboardStats,
    adminStats: AdminDashboardStats?,
    adminAccounts: [AdminAccountSnapshot] = [],
    opsSnapshot: OpsDashboardSnapshot? = nil,
    publicSettings: PublicSettings?,
    warning: String?,
    fetchedAt: Date = Date()
  ) {
    self.user = user
    self.userStats = userStats
    self.adminStats = adminStats
    self.adminAccounts = adminAccounts
    self.opsSnapshot = opsSnapshot
    self.publicSettings = publicSettings
    self.warning = warning
    self.fetchedAt = fetchedAt
  }
}

public enum MonitorSnapshot: Sendable, Equatable {
  case apiKey(APIKeyMonitorSnapshot)
  case adminAPIKey(AdminAPIKeyMonitorSnapshot)
  case account(AccountMonitorSnapshot)

  public var fetchedAt: Date {
    switch self {
    case .apiKey(let snapshot): snapshot.fetchedAt
    case .adminAPIKey(let snapshot): snapshot.fetchedAt
    case .account(let snapshot): snapshot.fetchedAt
    }
  }

  public var warning: String? {
    switch self {
    case .apiKey(let snapshot): snapshot.warning
    case .adminAPIKey(let snapshot): snapshot.warning
    case .account(let snapshot): snapshot.warning
    }
  }

  public var serverVersion: String? {
    switch self {
    case .apiKey(let snapshot): snapshot.publicSettings?.version
    case .adminAPIKey(let snapshot): snapshot.publicSettings?.version
    case .account(let snapshot): snapshot.publicSettings?.version
    }
  }

  public var displayName: String {
    switch self {
    case .apiKey(let snapshot):
      return snapshot.usage.planName ?? "API Key"
    case .adminAPIKey:
      return "管理员 API Key"
    case .account(let snapshot):
      return snapshot.user.username
    }
  }

  public var remaining: Double? {
    switch self {
    case .apiKey(let snapshot):
      return snapshot.usage.effectiveRemaining
    case .adminAPIKey:
      return nil
    case .account(let snapshot):
      return snapshot.user.balance
    }
  }

  public var todayCost: Double? {
    switch self {
    case .apiKey(let snapshot):
      return snapshot.usage.usage?.today?.actualCost
    case .adminAPIKey(let snapshot):
      return snapshot.stats.todayActualCost
    case .account(let snapshot):
      return snapshot.userStats.todayActualCost
    }
  }

  public var todayRequests: Int? {
    switch self {
    case .apiKey(let snapshot):
      return snapshot.usage.usage?.today?.requests
    case .adminAPIKey(let snapshot):
      return snapshot.stats.todayRequests
    case .account(let snapshot):
      return snapshot.userStats.todayRequests
    }
  }

  public var todayTokens: Int? {
    switch self {
    case .apiKey(let snapshot):
      return snapshot.usage.usage?.today?.totalTokens
    case .adminAPIKey(let snapshot):
      return snapshot.stats.todayTokens
    case .account(let snapshot):
      return snapshot.userStats.todayTokens
    }
  }

  public var rpm: Double? {
    switch self {
    case .apiKey(let snapshot):
      return snapshot.usage.usage?.rpm
    case .adminAPIKey(let snapshot):
      return snapshot.stats.rpm
    case .account(let snapshot):
      return snapshot.adminStats?.rpm ?? snapshot.userStats.rpm
    }
  }

  public var tpm: Double? {
    switch self {
    case .apiKey(let snapshot):
      return snapshot.usage.usage?.tpm
    case .adminAPIKey(let snapshot):
      return snapshot.stats.tpm
    case .account(let snapshot):
      return snapshot.adminStats?.tpm ?? snapshot.userStats.tpm
    }
  }

  public var averageDurationMs: Double? {
    switch self {
    case .apiKey(let snapshot):
      return snapshot.usage.usage?.averageDurationMs
    case .adminAPIKey(let snapshot):
      return snapshot.stats.averageDurationMs
    case .account(let snapshot):
      return snapshot.adminStats?.averageDurationMs ?? snapshot.userStats.averageDurationMs
    }
  }

  public var p95DurationMs: Double? {
    guard isAdmin else { return nil }
    switch self {
    case .adminAPIKey(let snapshot):
      return snapshot.opsSnapshot?.overview?.duration?.p95Ms.map(Double.init)
    case .account(let snapshot):
      return snapshot.opsSnapshot?.overview?.duration?.p95Ms.map(Double.init)
    case .apiKey:
      return nil
    }
  }

  public var errorRate: Double? {
    guard isAdmin else { return nil }
    switch self {
    case .adminAPIKey(let snapshot):
      return snapshot.opsSnapshot?.overview?.errorRate
    case .account(let snapshot):
      return snapshot.opsSnapshot?.overview?.errorRate
    case .apiKey:
      return nil
    }
  }

  public var sla: Double? {
    guard isAdmin else { return nil }
    switch self {
    case .adminAPIKey(let snapshot):
      return snapshot.opsSnapshot?.overview?.sla
    case .account(let snapshot):
      return snapshot.opsSnapshot?.overview?.sla
    case .apiKey:
      return nil
    }
  }

  public var adminStats: AdminDashboardStats? {
    switch self {
    case .adminAPIKey(let snapshot): snapshot.stats
    case .account(let snapshot): snapshot.adminStats
    case .apiKey: nil
    }
  }

  public var adminAccounts: [AdminAccountSnapshot] {
    switch self {
    case .adminAPIKey(let snapshot): snapshot.adminAccounts
    case .account(let snapshot): snapshot.adminAccounts
    case .apiKey: []
    }
  }

  public var supportsAdminAccountList: Bool {
    switch self {
    case .adminAPIKey: true
    case .account(let snapshot): snapshot.user.isAdmin
    case .apiKey: false
    }
  }

  public var isAdmin: Bool {
    switch self {
    case .adminAPIKey: true
    case .account(let snapshot): snapshot.user.isAdmin
    case .apiKey: false
    }
  }

  public var isAPIKey: Bool {
    if case .apiKey = self { return true }
    return false
  }

  public var isAdminAPIKey: Bool {
    if case .adminAPIKey = self { return true }
    return false
  }
}

public enum AuthenticationMode: String, CaseIterable, Codable, Sendable, Identifiable {
  case apiKey
  case adminAPIKey
  case account

  public var id: String { rawValue }

  public static func apiKeyMode(for rawAPIKey: String) -> Self? {
    let apiKey = rawAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
    if apiKey.hasPrefix("admin-") { return .adminAPIKey }
    if apiKey.hasPrefix("sk-") { return .apiKey }
    return nil
  }
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

public enum DashboardMetric: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
  case todayCost
  case todayRequests
  case todayTokens
  case averageDuration
  case p95Duration
  case errorRate
  case sla
  case rpm
  case tpm

  public var id: String { rawValue }

  public var requiresAdminOps: Bool {
    switch self {
    case .p95Duration, .errorRate, .sla:
      return true
    case .todayCost, .todayRequests, .todayTokens, .averageDuration, .rpm, .tpm:
      return false
    }
  }
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
  case adminComplianceRequired
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
    case .adminComplianceRequired:
      return "请先在 Sub2API Web 管理后台阅读并接受合规声明，然后重新连接。"
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
