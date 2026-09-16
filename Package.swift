// swift-tools-version: 5.10
// Copyright 2026 Meni Tasa
// SPDX-License-Identifier: LicenseRef-PolyForm-Perimeter-1.0.0

import PackageDescription

let package = Package(
    name: "JitPass",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "JitPass", targets: ["JitPassApp"]),
        .library(name: "JitAgentClient", targets: ["JitAgentClient"]),
    ],
    targets: [
        // The socket client: pure Foundation, no AppKit, fully testable.
        .target(name: "JitAgentClient"),
        // The menu bar app: AppKit only, a thin view over JitAgentClient.
        .executableTarget(
            name: "JitPassApp",
            dependencies: ["JitAgentClient"]
        ),
        .testTarget(
            name: "JitAgentClientTests",
            dependencies: ["JitAgentClient"]
        ),
    ]
)
