// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "Sub2APIConsole",
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .library(name: "Sub2APIKit", targets: ["Sub2APIKit"]),
    .executable(name: "Sub2APIConsole", targets: ["Sub2APIConsole"]),
  ],
  targets: [
    .target(
      name: "Sub2APIKit",
      linkerSettings: [
        .linkedFramework("Security")
      ]
    ),
    .executableTarget(
      name: "Sub2APIConsole",
      dependencies: ["Sub2APIKit"],
      linkerSettings: [
        .linkedFramework("AppKit"),
        .linkedFramework("ServiceManagement"),
      ]
    ),
    .testTarget(
      name: "Sub2APIKitTests",
      dependencies: ["Sub2APIKit"]
    ),
  ]
)
