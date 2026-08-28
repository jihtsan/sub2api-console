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
}
