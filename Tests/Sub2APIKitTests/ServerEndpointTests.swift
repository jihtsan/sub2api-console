import Foundation
import XCTest

@testable import Sub2APIKit

final class ServerEndpointTests: XCTestCase {
  func testBuildsAPIBaseFromRootAddress() throws {
    let endpoint = try ServerEndpoint("https://example.com/")

    XCTAssertEqual(endpoint.webBaseURL.absoluteString, "https://example.com/")
    XCTAssertEqual(endpoint.apiBaseURL.absoluteString, "https://example.com/api/v1")
    XCTAssertEqual(endpoint.gatewayBaseURL.absoluteString, "https://example.com/v1")
    XCTAssertEqual(
      try endpoint.url(path: "/auth/me").absoluteString,
      "https://example.com/api/v1/auth/me"
    )
    XCTAssertTrue(endpoint.isSecure)
  }

  func testPreservesReverseProxySubpathAndExistingAPIPrefix() throws {
    let endpoint = try ServerEndpoint("https://example.com/sub2api/api/v1/")

    XCTAssertEqual(endpoint.webBaseURL.absoluteString, "https://example.com/sub2api")
    XCTAssertEqual(endpoint.apiBaseURL.absoluteString, "https://example.com/sub2api/api/v1")
    XCTAssertEqual(endpoint.gatewayBaseURL.absoluteString, "https://example.com/sub2api/v1")
  }

  func testAddsTimezoneQuery() throws {
    let endpoint = try ServerEndpoint("http://localhost:8080")
    let url = try endpoint.url(
      path: "usage/dashboard/stats",
      queryItems: [URLQueryItem(name: "timezone", value: "Asia/Shanghai")]
    )

    XCTAssertEqual(url.scheme, "http")
    XCTAssertEqual(url.host, "localhost")
    XCTAssertEqual(url.port, 8080)
    XCTAssertEqual(
      URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value,
      "Asia/Shanghai")
    XCTAssertFalse(endpoint.isSecure)
  }

  func testRejectsUnsupportedOrCredentialedAddresses() {
    XCTAssertThrowsError(try ServerEndpoint("example.com"))
    XCTAssertThrowsError(try ServerEndpoint("ftp://example.com"))
    XCTAssertThrowsError(try ServerEndpoint("https://user:password@example.com"))
    XCTAssertThrowsError(try ServerEndpoint("https://example.com?token=secret"))
  }
}
