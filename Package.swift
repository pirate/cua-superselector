// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "SuperSelector",
  platforms: [.macOS(.v14)],
  products: [
    .executable(name: "SuperSelector", targets: ["SuperSelector"])
  ],
  targets: [
    .executableTarget(
      name: "SuperSelector",
      swiftSettings: [.swiftLanguageMode(.v5)]
    ),
    .testTarget(
      name: "SuperSelectorTests",
      dependencies: ["SuperSelector"],
      swiftSettings: [.swiftLanguageMode(.v5)]
    ),
  ]
)
