// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NotchBeat",
    platforms: [.macOS("14.2")],
    products: [.executable(name: "NotchBeat", targets: ["NotchBeat"])],
    targets: [.executableTarget(name: "NotchBeat")],
    swiftLanguageModes: [.v5]
)
