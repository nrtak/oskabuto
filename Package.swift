// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "PrivacyGuardCore", products: [.library(name: "PrivacyGuardCore", targets: ["PrivacyGuardCore"])], targets: [
    .target(name: "PrivacyGuardCore", path: "Shared", exclude: ["CallStore.swift"], sources: ["SafetyEngine.swift"]),
    .testTarget(name: "PrivacyGuardCoreTests", dependencies: ["PrivacyGuardCore"], path: "Tests")
])
