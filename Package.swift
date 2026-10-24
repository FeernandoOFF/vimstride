// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Vimstride",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Vimstride", targets: ["Vimstride"])],
    targets: [
        .target(name: "NavigationCore", path: "shared-core/Sources/NavigationCore"),
        .target(name: "MacNavigation", dependencies: ["NavigationCore"], path: "native/macos/Sources/MacNavigation"),
        .executableTarget(name: "Vimstride", dependencies: ["MacNavigation"], path: "Sources/Vimstride"),
        .testTarget(name: "NavigationCoreTests", dependencies: ["NavigationCore"]),
        .testTarget(name: "MacNavigationTests", dependencies: ["MacNavigation", "NavigationCore"]),
    ]
)
