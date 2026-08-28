import XCTest

@testable import Sub2APIKit

final class ServerVersionTests: XCTestCase {
  func testParsesTaggedAndPrereleaseVersions() {
    XCTAssertEqual(ServerVersion("v0.1.183"), ServerVersion(major: 0, minor: 1, patch: 183))
    XCTAssertEqual(
      ServerVersion("0.1.183-rc.1+build"),
      ServerVersion(major: 0, minor: 1, patch: 183)
    )
    XCTAssertNil(ServerVersion("development"))
  }

  func testComparesVersionsNumerically() {
    XCTAssertLessThan(
      ServerVersion(major: 0, minor: 1, patch: 99), ServerVersion(major: 0, minor: 1, patch: 172))
    XCTAssertGreaterThan(
      ServerVersion(major: 1, minor: 0, patch: 0), ServerVersion(major: 0, minor: 99, patch: 999))
  }
}
