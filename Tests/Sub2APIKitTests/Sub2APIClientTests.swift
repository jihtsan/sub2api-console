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
      session: StoredSession(accessToken: "old-panel-token")
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
              "mode": "wallet",
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

  func testAccountLoginStoresRotatingSessionAndClearsAPIKey() async throws {
    let credentials = InMemoryCredentialStore(apiKey: "old-api-key")
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
      email: "operator@example.com",
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

    XCTAssertEqual(requests.request(path: "/api/v1/auth/login")?.httpMethod, "POST")
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

  init(session: StoredSession? = nil, apiKey: String? = nil) {
    self.session = session
    self.apiKey = apiKey
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

  func clearAll() throws {
    lock.withLock {
      session = nil
      apiKey = nil
    }
  }
}

private final class RequestLog: @unchecked Sendable {
  private let lock = NSLock()
  private var requests: [URLRequest] = []

  var paths: [String] {
    lock.withLock { requests.compactMap(\.url?.path) }
  }

  func append(_ request: URLRequest) {
    lock.withLock { requests.append(request) }
  }

  func request(path: String) -> URLRequest? {
    lock.withLock { requests.first { $0.url?.path == path } }
  }

  func queryValue(named name: String, path: String) -> String? {
    guard let url = request(path: path)?.url else { return nil }
    return URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first {
      $0.name == name
    }?.value
  }
}
