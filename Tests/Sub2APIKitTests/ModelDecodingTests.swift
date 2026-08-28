import Foundation
import XCTest

@testable import Sub2APIKit

final class ModelDecodingTests: XCTestCase {
  func testDecodesUserDashboardEnvelopeWithOptionalVersionedFields() throws {
    let json = Data(
      """
      {
        "code": 0,
        "message": "success",
        "data": {
          "total_api_keys": 3,
          "today_requests": 42,
          "today_tokens": 12000,
          "today_actual_cost": 1.25,
          "average_duration_ms": 812.5,
          "rpm": 2.4,
          "tpm": 956.0,
          "future_field": true
        }
      }
      """.utf8
    )
    let envelope = try JSONDecoder().decode(APIEnvelope<UserDashboardStats>.self, from: json)

    XCTAssertEqual(envelope.code, 0)
    XCTAssertEqual(envelope.data?.totalAPIKeys, 3)
    XCTAssertEqual(envelope.data?.todayRequests, 42)
    XCTAssertEqual(envelope.data?.todayActualCost, 1.25)
    XCTAssertEqual(envelope.data?.averageDurationMs, 812.5)
  }

  func testDecodesTwoFactorLoginShape() throws {
    let json = Data(
      """
      {
        "code": 0,
        "message": "success",
        "data": {
          "requires_2fa": true,
          "temp_token": "temporary-login-token",
          "user_email_masked": "o***@example.com"
        }
      }
      """.utf8
    )
    let envelope = try JSONDecoder().decode(APIEnvelope<AuthPayload>.self, from: json)

    XCTAssertEqual(envelope.data?.requires2FA, true)
    XCTAssertEqual(envelope.data?.tempToken, "temporary-login-token")
  }

  func testCombinesUnhealthyAdminAccounts() throws {
    let json = Data(
      """
      {
        "error_accounts": 2,
        "ratelimit_accounts": 3,
        "overload_accounts": 1
      }
      """.utf8
    )
    let stats = try JSONDecoder().decode(AdminDashboardStats.self, from: json)

    XCTAssertEqual(stats.unhealthyAccounts, 6)
  }

  func testDecodesAdminAccountListWithCodexSevenDayUsageAndHealthState() throws {
    let json = Data(
      """
      {
        "code": 0,
        "message": "success",
        "data": {
          "items": [
            {
              "id": 42,
              "name": "primary-openai",
              "platform": "openai",
              "type": "oauth",
              "status": "active",
              "schedulable": false,
              "rate_limited_at": "2026-08-28T10:00:00Z",
              "rate_limit_reset_at": "2026-08-28T16:00:00Z",
              "extra": {
                "codex_7d_used_percent": 72.5,
                "codex_7d_reset_after_seconds": 86400,
                "codex_7d_reset_at": "2026-08-29T10:00:00Z",
                "future_field": "ignored"
              }
            }
          ],
          "total": 1,
          "page": 1,
          "page_size": 100,
          "pages": 1
        }
      }
      """.utf8
    )

    let envelope = try JSONDecoder().decode(
      APIEnvelope<AdminAccountPage>.self,
      from: json
    )
    let account = try XCTUnwrap(envelope.data?.items.first)
    let snapshot = AdminAccountSnapshot(account: account)

    XCTAssertEqual(account.id, 42)
    XCTAssertTrue(account.isRateLimited)
    XCTAssertFalse(account.schedulable ?? true)
    XCTAssertEqual(snapshot.sevenDayUsagePercent, 72.5)
    XCTAssertEqual(snapshot.sevenDayRemainingSeconds, 86_400)
    XCTAssertEqual(snapshot.sevenDayResetAt, "2026-08-29T10:00:00Z")
  }

  func testUsesGenericSevenDayUsageWhenCodexSnapshotIsMissing() throws {
    let json = Data(
      """
      {
        "usage": {
          "42": {
            "updated_at": "2026-08-28T10:05:00Z",
            "seven_day": {
              "utilization": 31.25,
              "resets_at": "2026-09-01T10:00:00Z",
              "remaining_seconds": 345600
            }
          }
        },
        "errors": {}
      }
      """.utf8
    )

    let batch = try JSONDecoder().decode(AdminAccountUsageBatchResponse.self, from: json)
    let usage = try XCTUnwrap(batch.usage["42"])
    let progress = try XCTUnwrap(usage.sevenDay)

    XCTAssertEqual(progress.utilization, 31.25)
    XCTAssertEqual(progress.remainingSeconds, 345_600)
    XCTAssertEqual(progress.resetsAt, "2026-09-01T10:00:00Z")
    XCTAssertTrue(batch.errors.isEmpty)
  }

  func testDecodesOpenAIQuotaRefreshAndResetCredits() throws {
    let refreshJSON = Data(
      """
      {
        "code": 0,
        "message": "success",
        "data": {
          "email": "operator@example.com",
          "plan_type": "plus",
          "rate_limit": {
            "allowed": false,
            "limit_reached": true,
            "primary_window": {
              "used_percent": 100,
              "limit_window_seconds": 18000,
              "reset_after_seconds": 900,
              "reset_at": 1788000000
            }
          },
          "rate_limit_reset_credits": {
            "available_count": 3,
            "credits": [{"expires_at": "2026-09-01T00:00:00Z"}]
          },
          "fetched_at": 1787999100,
          "cache_persisted": true
        }
      }
      """.utf8
    )
    let refresh = try JSONDecoder().decode(
      APIEnvelope<OpenAIQuotaRefreshResult>.self,
      from: refreshJSON
    )

    XCTAssertEqual(refresh.data?.email, "operator@example.com")
    XCTAssertEqual(refresh.data?.usage.availableResetCount, 3)
    XCTAssertEqual(refresh.data?.rateLimit?.primaryWindow?.resetAfterSeconds, 900)
    XCTAssertTrue(refresh.data?.cachePersisted == true)

    let resetJSON = Data(
      """
      {
        "code": 0,
        "message": "success",
        "data": {
          "code": "reset_success",
          "windows_reset": 1,
          "quota": {
            "rate_limit_reset_credits": {"available_count": 2},
            "fetched_at": 1787999200
          },
          "cache_refreshed": true,
          "account_state_recovered": true,
          "warning_code": "account_state_refresh_failed"
        }
      }
      """.utf8
    )
    let reset = try JSONDecoder().decode(
      APIEnvelope<OpenAIQuotaResetResult>.self,
      from: resetJSON
    )

    XCTAssertEqual(reset.data?.code, "reset_success")
    XCTAssertEqual(reset.data?.windowsReset, 1)
    XCTAssertEqual(reset.data?.quota?.availableResetCount, 2)
    XCTAssertTrue(reset.data?.cacheRefreshed == true)
    XCTAssertEqual(reset.data?.warningCode, "account_state_refresh_failed")
  }

  func testDecodesQuotaLimitedAPIKeyUsageWithoutTrustingIsValidAlone() throws {
    let json = Data(
      """
      {
        "mode": "quota_limited",
        "isValid": true,
        "status": "quota_exhausted",
        "quota": {
          "limit": 20,
          "used": 20,
          "remaining": 0,
          "unit": "USD"
        },
        "rate_limits": [
          {
            "window": "5h",
            "limit": 5,
            "used": 4.25,
            "remaining": 0.75,
            "reset_at": "2026-08-28T12:00:00Z"
          }
        ],
        "usage": {
          "today": {
            "requests": 18,
            "total_tokens": 24000,
            "actual_cost": 2.4
          },
          "rpm": 1.5,
          "tpm": 900
        }
      }
      """.utf8
    )

    let usage = try JSONDecoder().decode(APIKeyUsage.self, from: json)

    XCTAssertEqual(usage.effectiveRemaining, 0)
    XCTAssertEqual(usage.rateLimits?.first?.window, "5h")
    XCTAssertEqual(usage.usage?.today?.totalTokens, 24_000)
    XCTAssertFalse(usage.isOperational)
  }

  func testDecodesUnrestrictedSubscriptionWithMissingBestEffortUsage() throws {
    let json = Data(
      """
      {
        "mode": "unrestricted",
        "isValid": true,
        "planName": "Weekly",
        "remaining": 7.5,
        "unit": "USD",
        "subscription": {
          "weekly_usage_usd": 2.5,
          "weekly_limit_usd": 10,
          "expires_at": "2026-09-01T00:00:00Z"
        },
        "future_field": {"ignored": true}
      }
      """.utf8
    )

    let usage = try JSONDecoder().decode(APIKeyUsage.self, from: json)

    XCTAssertEqual(usage.planName, "Weekly")
    XCTAssertEqual(usage.subscription?.weeklyLimitUSD, 10)
    XCTAssertNil(usage.usage)
    XCTAssertTrue(usage.isOperational)
  }
}
