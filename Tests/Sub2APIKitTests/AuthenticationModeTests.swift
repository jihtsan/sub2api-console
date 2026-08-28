import XCTest

@testable import Sub2APIKit

final class AuthenticationModeTests: XCTestCase {
  func testDetectsAPIKeyModeFromPrefix() {
    XCTAssertEqual(
      AuthenticationMode.apiKeyMode(for: "  sk-example  ")?.rawValue,
      AuthenticationMode.apiKey.rawValue
    )
    XCTAssertEqual(
      AuthenticationMode.apiKeyMode(for: "admin-example")?.rawValue,
      AuthenticationMode.adminAPIKey.rawValue
    )
  }

  func testRejectsUnknownOrEmptyAPIKeyPrefix() {
    XCTAssertNil(AuthenticationMode.apiKeyMode(for: "example-key"))
    XCTAssertNil(AuthenticationMode.apiKeyMode(for: "   "))
  }
}
