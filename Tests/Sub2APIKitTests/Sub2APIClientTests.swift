import Foundation
import XCTest

@testable import Sub2APIKit

final class Sub2APIClientTests: XCTestCase, @unchecked Sendable {
  override func tearDown() {
    URLProtocolStub.handler = nil
    super.tearDown()
  }

  func testConnectsAPIKeyUsingRawGatewayUsageResponseAndReverseProxyPath() async throws {
    let credentials = InMemoryCredentialStore(
      session: StoredSession(accessToken: "old-panel-token"),
      adminAPIKey: "old-admin-key"
    )
    let requests = RequestLog()

    URLProtocolStub.handler = { request in
      requests.append(request)

      switch request.url?.path {
      case "/proxy/v1/usage":
        return Self.response(
          for: request,
          body: """
            {
              "mode": "unrestricted",
              "isValid": true,
              "planName": "Wallet",
              "remaining": 23.75,
              "unit": "USD",
              "usage": {
                "today": {
                  "requests": 12,
                  "total_tokens": 3456,
                  "actual_cost": 0.42
                },
                "average_duration_ms": 950,
                "rpm": 1.5,
                "tpm": 432
              }
            }
            """
        )
      case "/proxy/api/v1/settings/public":
        return Self.response(
          for: request,
          body: Self.envelope(
            """
            {
              "version": "v0.1.183",
              "site_name": "Example Sub2API"
            }
            """
          )
        )
      default:
        return Self.unexpectedResponse(for: request)
      }
    }

    let client = try Sub2APIClient(
      serverAddress: "https://sub2api.example.com/proxy/api/v1/",
      credentialStore: credentials,
      session: makeStubSession()
    )
    let snapshot = try await client.connectAPIKey("  sk-sub2api  ")

    XCTAssertEqual(snapshot.usage.remaining, 23.75)
    XCTAssertEqual(snapshot.usage.usage?.today?.requests, 12)
    XCTAssertEqual(snapshot.usage.usage?.today?.actualCost, 0.42)
    XCTAssertEqual(snapshot.publicSettings?.siteName, "Example Sub2API")
    XCTAssertEqual(try credentials.loadAPIKey(), "sk-sub2api")
    XCTAssertNil(try credentials.loadSession())
    XCTAssertNil(try credentials.loadAdminAPIKey())
    XCTAssertEqual(
      requests.request(path: "/proxy/v1/usage")?.value(forHTTPHeaderField: "Authorization"),
      "Bearer sk-sub2api"
    )
    XCTAssertEqual(requests.queryValue(named: "days", path: "/proxy/v1/usage"), "7")
    XCTAssertNotNil(requests.queryValue(named: "timezone", path: "/proxy/v1/usage"))
    XCTAssertEqual(
      requests.paths,
      ["/proxy/v1/usage", "/proxy/api/v1/settings/public"]
    )
  }

  func testConnectsAdminAPIKeyWithDedicatedHeaderAndClearsOtherCredentials() async throws {
    let credentials = InMemoryCredentialStore(
      session: StoredSession(accessToken: "old-panel-token"),
      apiKey: "old-gateway-key"
    )
    let requests = RequestLog()

    URLProtocolStub.handler = { request in
      requests.append(request)

      switch request.url?.path {
      case "/proxy/api/v1/admin/dashboard/stats":
        return Self.response(
          for: request,
          body: Self.envelope(
            """
            {
              "active_users": 14,
              "total_accounts": 20,
              "normal_accounts": 17,
              "error_accounts": 1,
              "ratelimit_accounts": 2,
              "today_requests": 321,
              "today_actual_cost": 4.25,
              "rpm": 3.5,
              "tpm": 840
            }
            """
          )
        )
      case "/proxy/api/v1/admin/accounts":
        return Self.response(
          for: request,
          body: Self.envelope(
            """
            {
              "items": [
                {
                  "id": 42,
                  "name": "primary-openai",
                  "platform": "openai",
                  "type": "oauth",
                  "status": "active",
                  "schedulable": true,
                  "extra": {
                    "codex_7d_used_percent": 72.5,
                    "codex_7d_reset_at": "2026-08-29T10:00:00Z"
                  }
                }
              ],
              "total": 1,
              "page": 1,
              "page_size": 100,
              "pages": 1
            }
            """
          )
        )
      case "/proxy/api/v1/admin/accounts/usage/batch":
        return Self.response(
          for: request,
          body: Self.envelope(
            """
            {
              "usage": {
                "42": {
                  "updated_at": "2026-08-28T10:05:00Z",
                  "seven_day": {
                    "utilization": 72.5,
                    "resets_at": "2026-08-29T10:00:00Z",
                    "remaining_seconds": 86400
                  }
                }
              },
              "errors": {}
            }
            """
          )
        )
      case "/proxy/api/v1/settings/public":
        return Self.response(
          for: request,
          body: Self.envelope("{\"version\":\"v0.1.183\"}")
        )
      default:
        return Self.unexpectedResponse(for: request)
      }
    }

    let client = try Sub2APIClient(
      serverAddress: "https://sub2api.example.com/proxy/api/v1/",
      credentialStore: credentials,
      session: makeStubSession()
    )
    let snapshot = try await client.connectAdminAPIKey("  admin-test-key  ")

    XCTAssertEqual(snapshot.stats.activeUsers, 14)
    XCTAssertEqual(snapshot.stats.unhealthyAccounts, 3)
    XCTAssertEqual(snapshot.adminAccounts.count, 1)
    XCTAssertEqual(snapshot.adminAccounts.first?.account.name, "primary-openai")
    XCTAssertEqual(snapshot.adminAccounts.first?.sevenDayUsagePercent, 72.5)
    XCTAssertEqual(try credentials.loadAdminAPIKey(), "admin-test-key")
    XCTAssertNil(try credentials.loadSession())
    XCTAssertNil(try credentials.loadAPIKey())

    let statsRequest = requests.request(path: "/proxy/api/v1/admin/dashboard/stats")
    XCTAssertEqual(statsRequest?.httpMethod, "GET")
    XCTAssertEqual(statsRequest?.value(forHTTPHeaderField: "x-api-key"), "admin-test-key")
    XCTAssertNil(statsRequest?.value(forHTTPHeaderField: "Authorization"))
    XCTAssertEqual(
      requests.paths,
      [
        "/proxy/api/v1/admin/dashboard/stats",
        "/proxy/api/v1/admin/accounts",
        "/proxy/api/v1/admin/accounts/usage/batch",
        "/proxy/api/v1/settings/public",
      ]
    )
    XCTAssertEqual(
      requests.request(path: "/proxy/api/v1/admin/accounts")?.value(forHTTPHeaderField: "x-api-key"),
      "admin-test-key"
    )
    XCTAssertEqual(
      requests.queryValue(named: "page_size", path: "/proxy/api/v1/admin/accounts"),
      "100"
    )
    XCTAssertEqual(
      requests.jsonBody(path: "/proxy/api/v1/admin/accounts/usage/batch")?["force"] as? Bool,
      false
    )
  }

  func testFetchesAdminAPIKeyListWithGroupAndTodayUsage() async throws {
    let credentials = InMemoryCredentialStore(adminAPIKey: "admin-list-key")
    let requests = RequestLog()

    URLProtocolStub.handler = { request in
      requests.append(request)

      switch request.url?.path {
      case "/proxy/api/v1/admin/users":
        return Self.response(
          for: request,
          body: Self.envelope(
            """
            {
              "items": [
                {"id": 7, "username": "alice", "email": "alice@example.com"},
                {"id": 8, "username": "bob", "email": "bob@example.com"}
              ],
              "total": 2,
              "page": 1,
              "page_size": 100,
              "pages": 1
            }
            """
          )
        )
      case "/proxy/api/v1/admin/users/7/api-keys":
        return Self.response(
          for: request,
          body: Self.envelope(
            """
            {
              "items": [
                {
                  "id": 101,
                  "user_id": 7,
                  "key": "sk-secret-value-that-must-not-be-rendered",
                  "name": "生产服务",
                  "group_id": 3,
                  "status": "active",
                  "group": {"id": 3, "name": "Claude"}
                }
              ],
              "total": 1,
              "page": 1,
              "page_size": 100,
              "pages": 1
            }
            """
          )
        )
      case "/proxy/api/v1/admin/users/8/api-keys":
        return Self.response(
          for: request,
          body: Self.envelope(
            """
            {
              "items": [
                {
                  "id": 102,
                  "user_id": 8,
                  "name": "备用服务",
                  "group_id": null,
                  "status": "disabled"
                }
              ],
              "total": 1,
              "page": 1,
              "page_size": 100,
              "pages": 1
            }
            """
          )
        )
      case "/proxy/api/v1/admin/dashboard/api-keys-trend":
        return Self.response(
          for: request,
          body: Self.envelope(
            """
            {
              "trend": [
                {"date": "2026-08-29", "api_key_id": 101, "key_name": "生产服务", "requests": 27, "tokens": 5000},
                {"date": "2026-08-29", "api_key_id": 101, "key_name": "生产服务", "requests": 3, "tokens": 700},
                {"date": "2026-08-29", "api_key_id": 102, "key_name": "备用服务", "requests": 5, "tokens": 100}
              ],
              "start_date": "2026-08-29",
              "end_date": "2026-08-29",
              "granularity": "day"
            }
            """
          )
        )
      default:
        return Self.unexpectedResponse(for: request)
      }
    }

    let client = try Sub2APIClient(
      serverAddress: "https://sub2api.example.com/proxy/api/v1/",
      credentialStore: credentials,
      session: makeStubSession()
    )
    let snapshot = try await client.fetchAdminAPIKeyList()

    let production = try XCTUnwrap(snapshot.items.first { $0.id == 101 })
    let fallback = try XCTUnwrap(snapshot.items.first { $0.id == 102 })
    XCTAssertEqual(production.displayName, "生产服务")
    XCTAssertEqual(production.groupName, "Claude")
    XCTAssertEqual(production.ownerDisplayName, "alice")
    XCTAssertEqual(production.todayRequests, 30)
    XCTAssertEqual(fallback.groupName, "未分组")
    XCTAssertEqual(fallback.ownerDisplayName, "bob")
    XCTAssertEqual(fallback.todayRequests, 5)
    XCTAssertNil(snapshot.warning)
    XCTAssertFalse(String(describing: snapshot).contains("sk-secret-value"))

    XCTAssertEqual(
      requests.queryValue(named: "include_subscriptions", path: "/proxy/api/v1/admin/users"),
      "false"
    )
    XCTAssertEqual(
      requests.queryValue(
        named: "limit",
        path: "/proxy/api/v1/admin/dashboard/api-keys-trend"
      ),
      "2"
    )
    XCTAssertEqual(
      requests.request(path: "/proxy/api/v1/admin/users")?.value(forHTTPHeaderField: "x-api-key"),
      "admin-list-key"
    )
    XCTAssertEqual(
      requests.request(path: "/proxy/api/v1/admin/dashboard/api-keys-trend")?
        .value(forHTTPHeaderField: "x-api-key"),
      "admin-list-key"
    )
  }

  func testOpenAIQuotaActionsUseDedicatedAdminAPIKeyHeader() async throws {
    let credentials = InMemoryCredentialStore(adminAPIKey: "admin-actions-key")
    let requests = RequestLog()
    URLProtocolStub.handler = { request in
      requests.append(request)
      switch request.url?.path {
      case "/api/v1/admin/openai/accounts/42/quota/refresh":
        return Self.response(
          for: request,
          body: Self.envelope(
            """
            {
              "user_id": "user-42",
              "account_id": "chatgpt-42",
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
                "available_count": 2,
                "credits": [{"expires_at": "2026-09-01T00:00:00Z"}]
              },
              "fetched_at": 1787999100,
              "cache_persisted": true
            }
            """
          )
        )
      case "/api/v1/admin/openai/accounts/42/reset-quota":
        return Self.response(
          for: request,
          body: Self.envelope(
            """
            {
              "code": "reset_success",
              "windows_reset": 1,
              "quota": {
                "account_id": "chatgpt-42",
                "rate_limit_reset_credits": {"available_count": 1},
                "fetched_at": 1787999200
              },
              "account": {
                "id": 42,
                "name": "primary-openai",
                "platform": "openai",
                "type": "oauth",
                "status": "active",
                "schedulable": true
              },
              "cache_refreshed": true,
              "account_state_recovered": true
            }
            """
          )
        )
      default:
        return Self.unexpectedResponse(for: request)
      }
    }

    let client = try Sub2APIClient(
      serverAddress: "https://sub2api.example.com",
      credentialStore: credentials,
      session: makeStubSession()
    )

    let refreshed = try await client.refreshOpenAIQuota(accountID: 42)
    let reset = try await client.resetOpenAIQuota(accountID: 42)

    XCTAssertEqual(refreshed.email, "operator@example.com")
    XCTAssertEqual(refreshed.usage.availableResetCount, 2)
    XCTAssertTrue(refreshed.cachePersisted)
    XCTAssertEqual(reset.account?.name, "primary-openai")
    XCTAssertEqual(reset.quota?.availableResetCount, 1)
    XCTAssertEqual(
      requests.paths,
      [
        "/api/v1/admin/openai/accounts/42/quota/refresh",
        "/api/v1/admin/openai/accounts/42/reset-quota",
      ]
    )
    for path in requests.paths {
      XCTAssertEqual(
        requests.request(path: path)?.value(forHTTPHeaderField: "x-api-key"),
        "admin-actions-key"
      )
      XCTAssertNil(requests.request(path: path)?.value(forHTTPHeaderField: "Authorization"))
      XCTAssertEqual(requests.request(path: path)?.httpMethod, "POST")
    }
  }

  func testOpenAIQuotaActionUsesSessionBearerForAdministratorAccount() async throws {
    let credentials = InMemoryCredentialStore(
      session: StoredSession(accessToken: "admin-session")
    )
    let requests = RequestLog()
    URLProtocolStub.handler = { request in
      requests.append(request)
      return Self.response(
        for: request,
        body: Self.envelope(
          """
          {
            "code": "reset_success",
            "windows_reset": 1,
            "cache_refreshed": true,
            "account_state_recovered": false
          }
          """
        )
      )
    }

    let client = try Sub2APIClient(
      serverAddress: "https://sub2api.example.com",
      credentialStore: credentials,
      session: makeStubSession()
    )

    let result = try await client.resetOpenAIQuota(accountID: 7)

    XCTAssertEqual(result.windowsReset, 1)
    XCTAssertEqual(
      requests.request(path: "/api/v1/admin/openai/accounts/7/reset-quota")?
        .value(forHTTPHeaderField: "Authorization"),
      "Bearer admin-session"
    )
    XCTAssertNil(
      requests.request(path: "/api/v1/admin/openai/accounts/7/reset-quota")?
        .value(forHTTPHeaderField: "x-api-key")
    )
  }

  func testDoesNotPersistRejectedAdminAPIKey() async throws {
    let credentials = InMemoryCredentialStore()
    let requests = RequestLog()
    URLProtocolStub.handler = { request in
      requests.append(request)
      return Self.response(
        for: request,
        status: 401,
        body: "{\"code\":401,\"message\":\"invalid admin api key\"}"
      )
    }

    let client = try Sub2APIClient(
      serverAddress: "https://sub2api.example.com",
      credentialStore: credentials,
      session: makeStubSession()
    )

    do {
      _ = try await client.connectAdminAPIKey("admin-invalid")
      XCTFail("Expected the admin API Key to be rejected")
    } catch let error as Sub2APIError {
      XCTAssertEqual(error, .unauthorized("invalid admin api key"))
    }
    XCTAssertNil(try credentials.loadAdminAPIKey())
    XCTAssertEqual(
      requests.request(path: "/api/v1/admin/dashboard/stats")?
        .value(forHTTPHeaderField: "x-api-key"),
      "admin-invalid"
    )
    XCTAssertNil(
      requests.request(path: "/api/v1/admin/dashboard/stats")?
        .value(forHTTPHeaderField: "Authorization")
    )
  }

  func testMapsAdminComplianceRequirementWithoutPersistingKey() async throws {
    let credentials = InMemoryCredentialStore()
    URLProtocolStub.handler = { request in
      Self.response(
        for: request,
        status: 423,
        body: "{\"code\":\"ADMIN_COMPLIANCE_ACK_REQUIRED\",\"message\":\"ack required\"}"
      )
    }

    let client = try Sub2APIClient(
      serverAddress: "https://sub2api.example.com",
      credentialStore: credentials,
      session: makeStubSession()
    )

    do {
      _ = try await client.connectAdminAPIKey("admin-compliance")
      XCTFail("Expected compliance acknowledgement to be required")
    } catch let error as Sub2APIError {
      XCTAssertEqual(error, .adminComplianceRequired)
    }
    XCTAssertNil(try credentials.loadAdminAPIKey())
  }

  func testAccountLoginStoresRotatingSessionAndClearsAPIKey() async throws {
    let credentials = InMemoryCredentialStore(
      apiKey: "old-api-key",
      adminAPIKey: "old-admin-key"
    )
    let requests = RequestLog()

    URLProtocolStub.handler = { request in
      requests.append(request)

      switch request.url?.path {
      case "/api/v1/settings/public":
        return Self.response(
          for: request,
          body: Self.envelope("{\"version\":\"v0.1.183\",\"totp_enabled\":true}")
        )
      case "/api/v1/auth/login":
        return Self.response(
          for: request,
          body: Self.envelope(
            """
            {
              "access_token": "panel-access",
              "refresh_token": "panel-refresh",
              "expires_in": 3600,
              "token_type": "Bearer",
              "user": {
                "id": 7,
                "username": "operator",
                "email": "operator@example.com",
                "role": "admin",
                "balance": 88.5
              }
            }
            """
          )
        )
      default:
        return Self.unexpectedResponse(for: request)
      }
    }

    let client = try Sub2APIClient(
      serverAddress: "https://sub2api.example.com",
      credentialStore: credentials,
      session: makeStubSession()
    )
    let result = try await client.login(
      email: "  operator@example.com \n",
      password: "secret-password"
    )

    guard case .authenticated(let user) = result else {
      return XCTFail("Expected an authenticated account")
    }
    XCTAssertEqual(user.username, "operator")
    XCTAssertTrue(user.isAdmin)
    XCTAssertEqual(try credentials.loadSession()?.accessToken, "panel-access")
    XCTAssertEqual(try credentials.loadSession()?.refreshToken, "panel-refresh")
    XCTAssertNotNil(try credentials.loadSession()?.expiresAt)
    XCTAssertNil(try credentials.loadAPIKey())
    XCTAssertNil(try credentials.loadAdminAPIKey())

    XCTAssertEqual(requests.request(path: "/api/v1/auth/login")?.httpMethod, "POST")
    XCTAssertEqual(
      requests.jsonBody(path: "/api/v1/auth/login")?["email"] as? String,
      "operator@example.com"
    )
  }

  func testRefreshesUnauthorizedSessionRotatesRefreshTokenAndRetries() async throws {
    let credentials = InMemoryCredentialStore(
      session: StoredSession(accessToken: "expired-token", refreshToken: "refresh-one")
    )
    let requests = RequestLog()

    URLProtocolStub.handler = { request in
      requests.append(request)
      let path = request.url?.path
      let authorization = request.value(forHTTPHeaderField: "Authorization")

      if path == "/api/v1/auth/me", authorization == "Bearer expired-token" {
        return Self.response(
          for: request,
          status: 401,
          body: "{\"code\":401,\"message\":\"token expired\"}"
        )
      }
      if path == "/api/v1/auth/refresh" {
        return Self.response(
          for: request,
          body: Self.envelope(
            """
            {
              "access_token": "fresh-token",
              "refresh_token": "refresh-two",
              "expires_in": 3600,
              "token_type": "Bearer"
            }
            """
          )
        )
      }
      if path == "/api/v1/auth/me", authorization == "Bearer fresh-token" {
        return Self.response(
          for: request,
          body: Self.envelope(
            """
            {
              "id": 9,
              "username": "refreshed",
              "email": "refreshed@example.com",
              "role": "user",
              "balance": 10
            }
            """
          )
        )
      }
      if path == "/api/v1/usage/dashboard/stats" {
        return Self.response(
          for: request,
          body: Self.envelope(
            "{\"today_requests\":21,\"today_actual_cost\":0.75,\"rpm\":2.5}"
          )
        )
      }
      if path == "/api/v1/settings/public" {
        return Self.response(
          for: request,
          body: Self.envelope("{\"version\":\"v0.1.183\"}")
        )
      }
      return Self.unexpectedResponse(for: request)
    }

    let client = try Sub2APIClient(
      serverAddress: "https://sub2api.example.com",
      credentialStore: credentials,
      session: makeStubSession()
    )
    let snapshot = try await client.fetchAccountSnapshot()

    XCTAssertEqual(snapshot.user.username, "refreshed")
    XCTAssertEqual(snapshot.userStats.todayRequests, 21)
    XCTAssertEqual(try credentials.loadSession()?.accessToken, "fresh-token")
    XCTAssertEqual(try credentials.loadSession()?.refreshToken, "refresh-two")
    XCTAssertEqual(
      requests.paths,
      [
        "/api/v1/auth/me",
        "/api/v1/auth/refresh",
        "/api/v1/auth/me",
        "/api/v1/usage/dashboard/stats",
        "/api/v1/settings/public",
      ]
    )
    XCTAssertEqual(requests.request(path: "/api/v1/auth/refresh")?.httpMethod, "POST")
  }

  func testRejectsNativeAccountLoginWhenCAPTCHAIsEnabled() async throws {
    let requests = RequestLog()
    URLProtocolStub.handler = { request in
      requests.append(request)
      return Self.response(
        for: request,
        body: Self.envelope(
          "{\"version\":\"v0.1.183\",\"turnstile_enabled\":true}"
        )
      )
    }

    let client = try Sub2APIClient(
      serverAddress: "https://sub2api.example.com",
      credentialStore: InMemoryCredentialStore(),
      session: makeStubSession()
    )

    do {
      _ = try await client.login(email: "user@example.com", password: "password")
      XCTFail("Expected CAPTCHA-enabled login to be rejected")
    } catch let error as Sub2APIError {
      XCTAssertEqual(error, .captchaRequired)
    }
    XCTAssertEqual(requests.paths, ["/api/v1/settings/public"])
  }

  func testRejectsAccountLoginOnKnownUnsafeServerVersion() async throws {
    let requests = RequestLog()
    URLProtocolStub.handler = { request in
      requests.append(request)
      return Self.response(
        for: request,
        body: Self.envelope("{\"version\":\"v0.1.171\"}")
      )
    }

    let client = try Sub2APIClient(
      serverAddress: "https://sub2api.example.com",
      credentialStore: InMemoryCredentialStore(),
      session: makeStubSession()
    )

    do {
      _ = try await client.login(email: "user@example.com", password: "password")
      XCTFail("Expected an unsafe server version to be rejected")
    } catch let error as Sub2APIError {
      XCTAssertEqual(error, .unsupportedServerVersion("v0.1.171"))
    }
    XCTAssertEqual(requests.paths, ["/api/v1/settings/public"])
  }

  func testMapsRetryAfterForRateLimitedAPIKeyRequest() async throws {
    let credentials = InMemoryCredentialStore()
    URLProtocolStub.handler = { request in
      Self.response(
        for: request,
        status: 429,
        headers: ["Retry-After": "120"],
        body: "{\"message\":\"too many requests\"}"
      )
    }

    let client = try Sub2APIClient(
      serverAddress: "https://sub2api.example.com",
      credentialStore: credentials,
      session: makeStubSession()
    )

    do {
      _ = try await client.connectAPIKey("sk-rate-limited")
      XCTFail("Expected the request to be rate limited")
    } catch let error as Sub2APIError {
      XCTAssertEqual(error, .rateLimited(retryAfter: 120))
    }
    XCTAssertNil(try credentials.loadAPIKey())
  }

  func testRejectsRemoteHTTPUnlessExplicitlyAllowed() throws {
    XCTAssertThrowsError(
      try Sub2APIClient(
        serverAddress: "http://sub2api.example.com",
        credentialStore: InMemoryCredentialStore(),
        session: makeStubSession()
      )
    ) { error in
      XCTAssertEqual(error as? Sub2APIError, .insecureServerAddress)
    }

    let allowed = try Sub2APIClient(
      serverAddress: "http://sub2api.example.com",
      credentialStore: InMemoryCredentialStore(),
      session: makeStubSession(),
      allowInsecureHTTP: true
    )
    XCTAssertEqual(allowed.webBaseURL.absoluteString, "http://sub2api.example.com/")
  }

  func testClearCredentialsRemovesEveryAuthenticationMode() async throws {
    let credentials = InMemoryCredentialStore(
      session: StoredSession(accessToken: "panel-token"),
      apiKey: "gateway-key",
      adminAPIKey: "admin-key"
    )
    let client = try Sub2APIClient(
      serverAddress: "https://sub2api.example.com",
      credentialStore: credentials,
      session: makeStubSession()
    )

    try await client.clearCredentials()

    XCTAssertNil(try credentials.loadSession())
    XCTAssertNil(try credentials.loadAPIKey())
    XCTAssertNil(try credentials.loadAdminAPIKey())
  }

  private func makeStubSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [URLProtocolStub.self]
    return URLSession(configuration: configuration)
  }

  private static func response(
    for request: URLRequest,
    status: Int = 200,
    headers: [String: String]? = nil,
    body: String
  ) -> (HTTPURLResponse, Data) {
    (
      HTTPURLResponse(
        url: request.url!,
        statusCode: status,
        httpVersion: nil,
        headerFields: headers
      )!,
      Data(body.utf8)
    )
  }

  private static func unexpectedResponse(for request: URLRequest) -> (HTTPURLResponse, Data) {
    response(
      for: request,
      status: 500,
      body: "{\"code\":500,\"message\":\"unexpected request\"}"
    )
  }

  private static func envelope(_ data: String) -> String {
    "{\"code\":0,\"message\":\"success\",\"data\":\(data)}"
  }
}

private final class URLProtocolStub: URLProtocol, @unchecked Sendable {
  nonisolated(unsafe) static var handler:
    (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    guard let handler = Self.handler else {
      client?.urlProtocol(self, didFailWithError: Sub2APIError.invalidResponse)
      return
    }

    do {
      let (response, data) = try handler(request)
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: data)
      client?.urlProtocolDidFinishLoading(self)
    } catch {
      client?.urlProtocol(self, didFailWithError: error)
    }
  }

  override func stopLoading() {}
}

private final class InMemoryCredentialStore: CredentialStoring, @unchecked Sendable {
  private let lock = NSLock()
  private var session: StoredSession?
  private var apiKey: String?
  private var adminAPIKey: String?

  init(
    session: StoredSession? = nil,
    apiKey: String? = nil,
    adminAPIKey: String? = nil
  ) {
    self.session = session
    self.apiKey = apiKey
    self.adminAPIKey = adminAPIKey
  }

  func loadSession() throws -> StoredSession? {
    lock.withLock { session }
  }

  func saveSession(_ session: StoredSession) throws {
    lock.withLock { self.session = session }
  }

  func clearSession() throws {
    lock.withLock { session = nil }
  }

  func loadAPIKey() throws -> String? {
    lock.withLock { apiKey }
  }

  func saveAPIKey(_ apiKey: String) throws {
    lock.withLock { self.apiKey = apiKey }
  }

  func clearAPIKey() throws {
    lock.withLock { apiKey = nil }
  }

  func loadAdminAPIKey() throws -> String? {
    lock.withLock { adminAPIKey }
  }

  func saveAdminAPIKey(_ apiKey: String) throws {
    lock.withLock { adminAPIKey = apiKey }
  }

  func clearAdminAPIKey() throws {
    lock.withLock { adminAPIKey = nil }
  }

  func clearAll() throws {
    lock.withLock {
      session = nil
      apiKey = nil
      adminAPIKey = nil
    }
  }
}

private final class RequestLog: @unchecked Sendable {
  private struct CapturedRequest {
    let request: URLRequest
    let body: Data?
  }

  private let lock = NSLock()
  private var requests: [CapturedRequest] = []

  var paths: [String] {
    lock.withLock { requests.compactMap(\.request.url?.path) }
  }

  func append(_ request: URLRequest) {
    let captured = CapturedRequest(request: request, body: Self.readBody(from: request))
    lock.withLock { requests.append(captured) }
  }

  func request(path: String) -> URLRequest? {
    lock.withLock { requests.first { $0.request.url?.path == path }?.request }
  }

  func queryValue(named name: String, path: String) -> String? {
    guard let url = request(path: path)?.url else { return nil }
    return URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first {
      $0.name == name
    }?.value
  }

  func jsonBody(path: String) -> [String: Any]? {
    let body = lock.withLock {
      requests.first { $0.request.url?.path == path }?.body
    }
    guard let body else { return nil }
    return try? JSONSerialization.jsonObject(with: body) as? [String: Any]
  }

  private static func readBody(from request: URLRequest) -> Data? {
    if let body = request.httpBody { return body }
    guard let stream = request.httpBodyStream else { return nil }

    stream.open()
    defer { stream.close() }

    var body = Data()
    var buffer = [UInt8](repeating: 0, count: 4_096)
    while true {
      let count = buffer.withUnsafeMutableBufferPointer { pointer in
        stream.read(pointer.baseAddress!, maxLength: pointer.count)
      }
      guard count >= 0 else { return nil }
      guard count > 0 else { return body }
      body.append(contentsOf: buffer.prefix(count))
    }
  }
}
