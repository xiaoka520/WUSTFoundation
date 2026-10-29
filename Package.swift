// swift-tools-version: 6.4
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "WUSTFoundation",
    platforms: [
        .iOS(.v15),
        .macOS(.v15),
        .visionOS(.v1),
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "WUSTFoundation",
            targets: ["WUSTFoundation"]
        ),
        .executable(name: "WUSTDemo", targets: ["WUSTDemo"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/scinfu/SwiftSoup.git",
            from: "2.14.3"
        )
    ],
    targets: [
        .target(
            name: "WUSTFoundation",
            dependencies: [
                .product(name: "SwiftSoup", package: "SwiftSoup")
            ],
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency")
            ],
        ),
        .testTarget(
            name: "WUSTFoundationTests",
            dependencies: ["WUSTFoundation"],
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency")
            ],
        ),
        .executableTarget(
            name: "WUSTDemo",
            dependencies: ["WUSTFoundation"],
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ]
        ),
    ]
)
