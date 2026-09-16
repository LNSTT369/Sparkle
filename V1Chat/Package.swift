// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SparkleChat",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "SparkleChat", targets: ["SparkleChat"])
    ],
    targets: [
        .executableTarget(
            name: "SparkleChat",
            path: "Sources/SparkleChat"
        )
    ]
)
