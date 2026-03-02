// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CallKit",
    platforms: [.iOS(.v14)],
    products: [
        .library(
            name: "CallKit",
            targets: ["FlutterCallkitIncomingPlugin"])
    ],
    dependencies: [
        .package(url: "https://github.com/ionic-team/capacitor-swift-pm.git", from: "7.0.0")
    ],
    targets: [
        .target(
            name: "FlutterCallkitIncomingPlugin",
            dependencies: [
                .product(name: "Capacitor", package: "capacitor-swift-pm"),
                .product(name: "Cordova", package: "capacitor-swift-pm")
            ],
            path: "ios/Classes/SwiftFlutterCallkitIncomingPlugin")
    ]
)