// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SparkleChat",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "SparkleChat", targets: ["SparkleChat"])
    ],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift", from: "0.21.0"),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", from: "2.25.0"),
    ],
    targets: [
        .executableTarget(
            name: "SparkleChat",
            dependencies: [
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXVLM", package: "mlx-swift-lm"),
            ],
            path: "Sources/SparkleChat"
        )
    ]
)
