// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DesktopIconBilliards",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "BilliardsCore", path: "Sources/BilliardsCore"),
        .target(name: "BilliardsApp", dependencies: ["BilliardsCore"],
                path: "Sources/DesktopIconBilliards"),
        .executableTarget(name: "DesktopIconBilliards", dependencies: ["BilliardsApp"],
                          path: "Sources/Entry"),
        .executableTarget(name: "PhysicsTests", dependencies: ["BilliardsCore"],
                          path: "Tests/PhysicsTests"),
        .executableTarget(name: "AppTests", dependencies: ["BilliardsApp"],
                          path: "Tests/AppTests"),
    ]
)